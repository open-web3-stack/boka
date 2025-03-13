import Foundation
import Logging
import MsQuicSwift
import Utils

public typealias NetAddr = MsQuicSwift.NetAddr

public enum StreamType: Sendable {
    case uniquePersistent
    case commonEphemeral
}

public enum PeerRole: String, Codable, Sendable, Hashable {
    case validator
    case builder
    // case proxy // not yet specified
}

struct BackoffState {
    var attempt: Int
    var delay: TimeInterval

    init(_ attempt: Int = 0, _ delay: TimeInterval = 1) {
        self.attempt = attempt
        self.delay = delay
    }

    mutating func applyBackoff() {
        attempt += 1
        delay *= 2
    }
}

public struct PeerOptions<Handler: StreamHandler>: Sendable {
    public var role: PeerRole
    public var listenAddress: NetAddr
    public var genesisHeader: Data32
    public var secretKey: Ed25519.SecretKey
    public var persistentStreamHandler: Handler.PresistentHandler
    public var ephemeralStreamHandler: Handler.EphemeralHandler
    public var serverSettings: QuicSettings
    public var clientSettings: QuicSettings
    public var peerSettings: PeerSettings

    public init(
        role: PeerRole,
        listenAddress: NetAddr,
        genesisHeader: Data32,
        secretKey: Ed25519.SecretKey,
        persistentStreamHandler: Handler.PresistentHandler,
        ephemeralStreamHandler: Handler.EphemeralHandler,
        serverSettings: QuicSettings = .defaultSettings,
        clientSettings: QuicSettings = .defaultSettings,
        peerSettings: PeerSettings = .defaultSettings
    ) {
        self.role = role
        self.listenAddress = listenAddress
        self.genesisHeader = genesisHeader
        self.secretKey = secretKey
        self.persistentStreamHandler = persistentStreamHandler
        self.ephemeralStreamHandler = ephemeralStreamHandler
        self.serverSettings = serverSettings
        self.clientSettings = clientSettings
        self.peerSettings = peerSettings
    }
}

// TODO: peer reputation system to ban peers not following the protocol
public final class Peer<Handler: StreamHandler>: Sendable {
    private let impl: PeerImpl<Handler>

    private let listener: QuicListener

    private var logger: Logger {
        impl.logger
    }

    public let publicKey: Data
    public init(options: PeerOptions<Handler>) throws {
        let logger = Logger(label: "Peer".uniqueId)

        let alpns = [
            PeerRole.validator: Alpn(genesisHeader: options.genesisHeader, builder: false).data,
            PeerRole.builder: Alpn(genesisHeader: options.genesisHeader, builder: true).data,
        ]
        let allAlpns = Array(alpns.values)

        let pkcs12 = try generateSelfSignedCertificate(privateKey: options.secretKey)

        let registration = try QuicRegistration()
        let serverConfiguration = try QuicConfiguration(
            registration: registration, pkcs12: pkcs12, alpns: allAlpns, client: false,
            settings: options.serverSettings
        )

        let clientAlpn = alpns[options.role]!
        let clientConfiguration = try QuicConfiguration(
            registration: registration, pkcs12: pkcs12, alpns: [clientAlpn], client: true,
            settings: options.clientSettings
        )

        publicKey = options.secretKey.publicKey.data.data

        impl = PeerImpl(
            logger: logger,
            role: options.role,
            settings: options.peerSettings,
            alpns: alpns,
            publicKey: publicKey,
            clientConfiguration: clientConfiguration,
            persistentStreamHandler: options.persistentStreamHandler,
            ephemeralStreamHandler: options.ephemeralStreamHandler
        )

        listener = try QuicListener(
            handler: PeerEventHandler(impl),
            registration: registration,
            configuration: serverConfiguration,
            listenAddress: options.listenAddress,
            alpns: allAlpns
        )

        logger.debug(
            "Peer initialized",
            metadata: [
                "listenAddress": "\(options.listenAddress)",
                "role": "\(options.role)",
                "publicKey": "\(options.secretKey.publicKey.data.toHexString())",
            ]
        )
    }

    public func listenAddress() throws -> NetAddr {
        try listener.listenAddress()
    }

    // TODO: see if we can remove the role parameter
    @discardableResult
    public func connect(to address: NetAddr, role: PeerRole) throws -> Connection<Handler> {
        let conn = impl.connections.read { connections in
            connections.byAddr[address]
        }
        return try conn
            ?? impl.connections.write { connections in
                if let curr = connections.byAddr[address] {
                    return curr
                }

                logger.debug(
                    "Connecting to peer",
                    metadata: [
                        "address": "\(address)",
                        "role": "\(role)",
                        "initiatedByLocal": "true",
                    ]
                )

                let quicConn = try QuicConnection(
                    handler: PeerEventHandler(self.impl),
                    registration: self.impl.clientConfiguration.registration,
                    configuration: self.impl.clientConfiguration
                )
                try quicConn.connect(to: address)
                let conn = Connection(
                    quicConn,
                    impl: self.impl,
                    role: role,
                    remoteAddress: address,
                    initiatedByLocal: true
                )
                connections.byAddr[address] = conn
                connections.byId[conn.id] = conn
                return conn
            }
    }

    public func getConnection(publicKey: Data) -> Connection<Handler>? {
        let connection = impl.connections.read { connections in
            connections.byPublicKey[publicKey]
        }
        if let connection, connection.isClosed {
            return nil
        }
        return connection
    }

    public func broadcast(
        kind: Handler.PresistentHandler.StreamKind, message: Handler.PresistentHandler.Message
    ) {
        guard let messageData = try? message.encode() else {
            impl.logger.warning(
                "Failed to encode message",
                metadata: [
                    "messageType": "\(type(of: message))",
                    "error": "Encoding failure",
                ]
            )
            return
        }
        let connections = impl.connections.read { connections in
            connections.byId.values
        }
        for connection in connections {
            if connection.isClosed {
                continue
            }
            if let stream = try? connection.createPreistentStream(kind: kind) {
                Task {
                    let res = await Result {
                        for chunk in messageData {
                            try await stream.send(message: chunk)
                        }
                    }
                    switch res {
                    case .success:
                        break
                    case let .failure(error):
                        impl.logger.warning(
                            "Failed to send message",
                            metadata: [
                                "connectionId": "\(connection.id)",
                                "kind": "\(kind)",
                                "message": "\(messageData)",
                                "error": "\(error)",
                            ]
                        )
                    }
                }
            }
        }
    }

    // there should be only one connection per peer
    // exclude closed connections
    public var peersCount: Int {
        impl.connections.read { $0.byId.count { $0.value.isClosed == false } }
    }

    public var peersRole: PeerRole {
        impl.role
    }
}

final class PeerImpl<Handler: StreamHandler>: Sendable {
    struct ConnectionStorage {
        var byAddr: [NetAddr: Connection<Handler>] = [:]
        var byId: [UniqueId: Connection<Handler>] = [:]
        var byPublicKey: [Data: Connection<Handler>] = [:]
    }

    fileprivate let logger: Logger
    fileprivate let role: PeerRole
    fileprivate let settings: PeerSettings
    fileprivate let alpns: [PeerRole: Data]
    fileprivate let alpnLookup: [Data: PeerRole]
    fileprivate let publicKey: Data

    fileprivate let clientConfiguration: QuicConfiguration

    fileprivate let connections: ThreadSafeContainer<ConnectionStorage> = .init(.init())
    fileprivate let streams: ThreadSafeContainer<[UniqueId: Stream<Handler>]> = .init([:])
    fileprivate let reconnectStates: ThreadSafeContainer<[NetAddr: BackoffState]> = .init([:])
    fileprivate let reopenStates: ThreadSafeContainer<[UniqueId: BackoffState]> = .init([:])

    let maxRetryAttempts = 5
    let persistentStreamHandler: Handler.PresistentHandler
    let ephemeralStreamHandler: Handler.EphemeralHandler

    fileprivate init(
        logger: Logger,
        role: PeerRole,
        settings: PeerSettings,
        alpns: [PeerRole: Data],
        publicKey: Data,
        clientConfiguration: QuicConfiguration,
        persistentStreamHandler: Handler.PresistentHandler,
        ephemeralStreamHandler: Handler.EphemeralHandler
    ) {
        self.logger = logger
        self.role = role
        self.settings = settings
        self.alpns = alpns
        self.publicKey = publicKey
        self.clientConfiguration = clientConfiguration
        self.persistentStreamHandler = persistentStreamHandler
        self.ephemeralStreamHandler = ephemeralStreamHandler

        var alpnLookup = [Data: PeerRole]()
        for (role, alpn) in alpns {
            alpnLookup[alpn] = role
        }
        self.alpnLookup = alpnLookup
    }

    func addConnection(_ connection: QuicConnection, addr: NetAddr, role: PeerRole) -> Bool {
        connections.write { connections in
            if role == .builder {
                let currentCount = connections.byAddr.values.filter { $0.role == role }.count
                if currentCount >= self.settings.maxBuilderConnections {
                    if let conn = connections.byAddr.values.filter({ $0.role == .builder })
                        .sorted(by: { $0.getLastActive() < $1.getLastActive() }).first
                    {
                        self.logger.debug(
                            "Replacing least active builder connection",
                            metadata: [
                                "address": "\(conn.remoteAddress)",
                                "connectionId": "\(conn.id)",
                                "lastActive": "\(conn.getLastActive())",
                            ]
                        )
                        conn.close(abort: false)
                    } else {
                        self.logger.warning("Max builder connections reached, no eligible replacement found")
                        return false
                    }
                }
            }
            if connections.byAddr[addr] != nil {
                self.logger.warning(
                    "Connection already exists",
                    metadata: [
                        "address": "\(addr)",
                        "role": "\(role)",
                    ]
                )
                return false
            }
            let conn = Connection(
                connection,
                impl: self,
                role: role,
                remoteAddress: addr,
                initiatedByLocal: false
            )
            connections.byAddr[addr] = conn
            connections.byId[connection.id] = conn
            return true
        }
    }

    func reconnect(to address: NetAddr, role: PeerRole) throws {
        var state = reconnectStates.read { reconnectStates in
            reconnectStates[address] ?? .init()
        }
        logger.debug(
            "Reconnecting to peer",
            metadata: [
                "address": "\(address)",
                "attempt": "\(state.attempt + 1)/\(maxRetryAttempts)",
                "delay": "\(state.delay)s",
                "role": "\(role)",
            ]
        )
        guard state.attempt < maxRetryAttempts else {
            logger.warning(
                "Reconnection attempts exceeded",
                metadata: [
                    "address": "\(address)",
                    "maxAttempts": "\(maxRetryAttempts)",
                    "role": "\(role)",
                ]
            )
            return
        }
        state.applyBackoff()
        reconnectStates.write { reconnectStates in
            reconnectStates[address] = state
        }
        Task {
            try await Task.sleep(for: .seconds(state.delay))
            try connections.write { connections in
                if connections.byAddr[address] != nil {
                    logger.debug(
                        "Skipping reconnection - already connected",
                        metadata: ["address": "\(address)", "role": "\(role)"]
                    )
                    return
                }
                let quicConn = try QuicConnection(
                    handler: PeerEventHandler(self),
                    registration: clientConfiguration.registration,
                    configuration: clientConfiguration
                )
                try quicConn.connect(to: address)
                let conn = Connection(
                    quicConn,
                    impl: self,
                    role: role,
                    remoteAddress: address,
                    initiatedByLocal: true
                )
                connections.byAddr[address] = conn
                connections.byId[conn.id] = conn
            }
        }
    }

    func reopenUpStream(connection: Connection<Handler>, kind: Handler.PresistentHandler.StreamKind) {
        if connection.isClosed {
            logger.debug(
                "Connection is closed, skipping reopen",
                metadata: [
                    "connectionId": "\(connection.id)",
                    "streamKind": "\(kind)",
                ]
            )
            return
        }

        var state = reopenStates.read { states in
            states[connection.id] ?? .init()
        }

        logger.debug(
            "Attempting to reopen stream",
            metadata: [
                "connectionId": "\(connection.id)",
                "streamKind": "\(kind)",
                "attempt": "\(state.attempt + 1)/\(maxRetryAttempts)",
                "delay": "\(state.delay)s",
            ]
        )
        guard state.attempt < maxRetryAttempts else {
            logger.warning(
                "Stream reopen attempts exceeded",
                metadata: [
                    "connectionId": "\(connection.id)",
                    "streamKind": "\(kind)",
                    "maxAttempts": "\(maxRetryAttempts)",
                ]
            )
            return
        }
        state.applyBackoff()
        reopenStates.write { states in
            states[connection.id] = state
        }

        Task {
            try await Task.sleep(for: .seconds(state.delay))
            do {
                logger.debug(
                    "Reopening persistent stream",
                    metadata: [
                        "connectionId": "\(connection.id)",
                        "streamKind": "\(kind)",
                    ]
                )
                try connection.createPreistentStream(kind: kind)
            } catch {
                logger.error(
                    "Failed to reopen persistent stream",
                    metadata: [
                        "connectionId": "\(connection.id)",
                        "streamKind": "\(kind)",
                        "error": "\(error)",
                    ]
                )
                reopenUpStream(connection: connection, kind: kind)
            }
        }
    }

    func addStream(_ stream: Stream<Handler>) {
        streams.write { streams in
            if streams[stream.id] != nil {
                self.logger.warning(
                    "Stream already exists",
                    metadata: ["streamId": "\(stream.id)"]
                )
            }
            streams[stream.id] = stream
        }
    }
}

private struct PeerEventHandler<Handler: StreamHandler>: QuicEventHandler {
    private let impl: PeerImpl<Handler>

    private var logger: Logger {
        impl.logger
    }

    init(_ impl: PeerImpl<Handler>) {
        self.impl = impl
    }

    func newConnection(_: QuicListener, connection: QuicConnection, info: ConnectionInfo)
        -> QuicStatus
    {
        let addr = info.remoteAddress
        let role = impl.alpnLookup[info.negotiatedAlpn]
        guard let role else {
            logger.warning(
                "Unknown ALPN protocol negotiation",
                metadata: [
                    "connectionId": "\(connection.id)",
                    "remoteAddress": "\(addr)",
                    "negotiatedAlpn": "\(String(data: info.negotiatedAlpn, encoding: .utf8) ?? info.negotiatedAlpn.toDebugHexString())",
                ]
            )
            return .code(.alpnNegFailure)
        }

        logger.debug(
            "New incoming connection",
            metadata: [
                "connectionId": "\(connection.id)",
                "remoteAddress": "\(addr)",
                "role": "\(role)",
            ]
        )

        if impl.addConnection(connection, addr: addr, role: role) {
            logger.debug(
                "Connection accepted",
                metadata: [
                    "connectionId": "\(connection.id)",
                    "remoteAddress": "\(addr)",
                    "role": "\(role)",
                ]
            )
            return .code(.success)
        } else {
            logger.debug(
                "Connection refused",
                metadata: [
                    "connectionId": "\(connection.id)",
                    "remoteAddress": "\(addr)",
                    "role": "\(role)",
                ]
            )
            return .code(.connectionRefused)
        }
    }

    func shouldOpen(_ connection: QuicConnection, certificate: Data?) -> QuicStatus {
        guard let certificate else {
            logger.warning(
                "Missing certificate in connection",
                metadata: [
                    "connectionId": "\(connection.id)",
                ]
            )
            return .code(.requiredCert)
        }

        let conn = impl.connections.read { connections in
            connections.byId[connection.id]
        }

        guard let conn else {
            logger.warning(
                "Attempt to open connection not in registry",
                metadata: [
                    "connectionId": "\(connection.id)",
                ]
            )
            return .code(.connectionRefused)
        }

        do {
            let (publicKey, alternativeName) = try parseCertificate(data: certificate, type: .x509)
            logger.trace(
                "Certificate parsed",
                metadata: [
                    "connectionId": "\(connection.id)",
                    "publicKey": "\(publicKey.toHexString())",
                    "alternativeName": "\(alternativeName)",
                    "remoteAddress": "\(conn.remoteAddress)",
                ]
            )

            if publicKey == impl.publicKey {
                // Self connection detected
                logger.debug(
                    "Rejecting self-connection",
                    metadata: [
                        "connectionId": "\(connection.id)",
                        "remoteAddress": "\(conn.remoteAddress)",
                    ]
                )
                return .code(.connectionRefused)
            }
            if alternativeName != generateSubjectAlternativeName(pubkey: publicKey) {
                return .code(.badCert)
            }
            // TODO: verify if it is current or next validator

            // Check for an existing connection by public key
            return try impl.connections.write { connections in
                if let existingConnection = connections.byPublicKey[publicKey] {
                    // Deterministically decide based on public key comparison
                    if !publicKey.lexicographicallyPrecedes(impl.publicKey) {
                        // We win the lexicographical comparison, we keep this connection
                        connections.byPublicKey[publicKey] = conn
                        existingConnection.close()
                        try conn.opened(publicKey: publicKey)
                        return .code(.success)
                    } else {
                        logger.debug(
                            "Rejecting duplicate connection by lexicographical rule",
                            metadata: [
                                "connectionId": "\(connection.id)",
                                "publicKey": "\(publicKey.toHexString())",
                                "remoteAddress": "\(conn.remoteAddress)",
                            ]
                        )
                        // Mark the connection state so streams won't be processed
                        conn.closing()
                        return .code(.connectionRefused)
                    }
                } else {
                    connections.byPublicKey[publicKey] = conn
                    try conn.opened(publicKey: publicKey)
                    return .code(.success)
                }
            }
        } catch {
            logger.warning(
                "Certificate parsing failed",
                metadata: [
                    "connectionId": "\(connection.id)",
                    "error": "\(error)",
                    "remoteAddress": "\(conn.remoteAddress)",
                ]
            )
            return .code(.badCert)
        }
    }

    func connected(_ connection: QuicConnection) {
        let conn = impl.connections.read { connections in
            connections.byId[connection.id]
        }
        guard let conn else {
            logger.warning(
                "Connection established but missing in registry",
                metadata: [
                    "connectionId": "\(connection.id)",
                ]
            )
            return
        }

        logger.debug(
            "Connection established",
            metadata: [
                "connectionId": "\(connection.id)",
                "remoteAddress": "\(conn.remoteAddress)",
                "initiatedByLocal": "\(conn.initiatedByLocal)",
            ]
        )

        impl.reconnectStates.write { reconnectStates in
            reconnectStates[conn.remoteAddress] = nil
        }

        if conn.initiatedByLocal {
            logger.debug(
                "Connection initiated by local, creating persistent streams",
                metadata: [
                    "connectionId": "\(connection.id)",
                    "remoteAddress": "\(conn.remoteAddress)",
                ]
            )
            for kind in Handler.PresistentHandler.StreamKind.allCases {
                do {
                    try conn.createPreistentStream(kind: kind)
                } catch {
                    logger.warning(
                        "Failed to create persistent stream. Closing connection...",
                        metadata: [
                            "connectionId": "\(connection.id)",
                            "kind": "\(kind)",
                            "error": "\(error)",
                            "remoteAddress": "\(conn.remoteAddress)",
                        ]
                    )
                    try? connection.shutdown(errorCode: 1) // TODO: define some error code
                    break
                }
            }
        }
    }

    func shutdownComplete(_ connection: QuicConnection) {
        logger.debug(
            "Connection shutdown complete",
            metadata: [
                "connectionId": "\(connection.id)",
            ]
        )
        let conn = impl.connections.read { connections in
            connections.byId[connection.id]
        }
        let needReconnect = impl.connections.write { connections in
            var needReconnect = false
            if let conn = connections.byId[connection.id] {
                needReconnect = conn.needReconnect
                if let publicKey = conn.publicKey, let existingConn = connections.byPublicKey[publicKey], existingConn === conn {
                    connections.byPublicKey.removeValue(forKey: publicKey)
                }
                connections.byId.removeValue(forKey: connection.id)
                connections.byAddr.removeValue(forKey: conn.remoteAddress)
                conn.closed()
            }
            return needReconnect
        }
        if needReconnect, let address = conn?.remoteAddress, let role = conn?.role {
            do {
                try impl.reconnect(to: address, role: role)
            } catch {
                logger.error(
                    "Reconnection failed",
                    metadata: [
                        "error": "\(error)",
                        "address": "\(address)",
                    ]
                )
            }
        }
    }

    func shutdownInitiated(_ connection: QuicConnection, reason: ConnectionCloseReason) {
        logger.debug(
            "Connection shutdown initiated",
            metadata: [
                "connectionId": "\(connection.id)",
                "reason": "\(reason)",
                "willReconnect": "\(shouldReconnect(basedOn: reason))",
            ]
        )
        if shouldReconnect(basedOn: reason) {
            impl.connections.write { connections in
                if let conn = connections.byId[connection.id] {
                    if let publicKey = conn.publicKey {
                        connections.byPublicKey.removeValue(forKey: publicKey)
                        conn.reconnect(publicKey: publicKey)
                    }
                }
            }
        }
    }

    // TODO: Add all the cases about reconnects
    private func shouldReconnect(basedOn reason: ConnectionCloseReason) -> Bool {
        switch reason {
        case .idle:
            // Do not reconnect for idle closures.
            false
        case let .transport(status, _):
            switch QuicStatusCode(rawValue: status.rawValue) {
            case .aborted, .outOfMemory, .connectionTimeout, .unreachable, .bufferTooSmall, .connectionRefused:
                true
            default:
                status.isSucceeded
            }
        case let .byPeer(code):
            // Do not reconnect if the closure was initiated by the peer.
            code != .success
        case let .byLocal(code):
            // Do not reconnect if the local side initiated the closure.
            code != .success
        }
    }

    func streamStarted(_ connection: QuicConnection, stream: QuicStream) {
        let conn = impl.connections.read { connections in
            connections.byId[connection.id]
        }
        if let conn {
            logger.debug(
                "Stream started",
                metadata: [
                    "connectionId": "\(connection.id)",
                    "streamId": "\(stream.id)",
                    "remoteAddress": "\(conn.remoteAddress)",
                ]
            )

            conn.streamStarted(stream: stream)
            // Reset reopen backoff state when a stream is successfully started
            impl.reopenStates.write { states in
                states[conn.id] = nil
            }
        } else {
            logger.warning(
                "Stream started on unknown connection",
                metadata: [
                    "connectionId": "\(connection.id)",
                    "streamId": "\(stream.id)",
                ]
            )
        }
    }

    func dataReceived(_ stream: QuicStream, data: Data?) {
        let stream = impl.streams.read { streams in
            streams[stream.id]
        }
        if let stream {
            stream.received(data: data)
            let connection = impl.connections.read { connections in
                connections.byId[stream.connectionId]
            }
            connection?.updateLastActive()
        }
    }

    func closed(_ quicStream: QuicStream, status: QuicStatus, code _: QuicErrorCode) {
        let stream = impl.streams.write { streams in
            streams.removeValue(forKey: quicStream.id)
        }

        if let stream {
            let connection = impl.connections.read { connections in
                connections.byId[stream.connectionId]
            }
            if let connection {
                connection.streamClosed(stream: stream, abort: !status.isSucceeded)
                if shouldReopenStream(connection: connection, stream: stream, status: status) {
                    if let kind = stream.kind {
                        impl.reopenUpStream(connection: connection, kind: kind)
                    }
                }
            } else {
                logger.warning(
                    "Stream closed but connection is missing",
                    metadata: [
                        "streamId": "\(stream.id)",
                    ]
                )
            }
        } else {
            logger.warning(
                "Stream closed but stream is missing from registry",
                metadata: [
                    "streamId": "\(quicStream.id)",
                ]
            )
        }
    }

    // TODO: Add all the cases about reopen up stream
    private func shouldReopenStream(connection: Connection<Handler>, stream: Stream<Handler>, status: QuicStatus) -> Bool {
        // Only reopen if the stream is a persistent UP stream and the closure was unexpected
        if connection.isClosed || connection.needReconnect || stream.kind == nil {
            return false
        }
        switch QuicStatusCode(rawValue: status.rawValue) {
        case .connectionIdle, .badCert:
            return false
        default:
            return status.isSucceeded
        }
    }
}
