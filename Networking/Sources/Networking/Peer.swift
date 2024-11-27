import Foundation
import Logging
import MsQuicSwift
import Utils

public typealias NetAddr = MsQuicSwift.NetAddr

public enum StreamType: Sendable {
    case uniquePersistent
    case commonEphemeral
}

public enum PeerRole: Sendable, Hashable {
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
    public var presistentStreamHandler: Handler.PresistentHandler
    public var ephemeralStreamHandler: Handler.EphemeralHandler
    public var serverSettings: QuicSettings
    public var clientSettings: QuicSettings
    public var peerSettings: PeerSettings

    public init(
        role: PeerRole,
        listenAddress: NetAddr,
        genesisHeader: Data32,
        secretKey: Ed25519.SecretKey,
        presistentStreamHandler: Handler.PresistentHandler,
        ephemeralStreamHandler: Handler.EphemeralHandler,
        serverSettings: QuicSettings = .defaultSettings,
        clientSettings: QuicSettings = .defaultSettings,
        peerSettings: PeerSettings = .defaultSettings
    ) {
        self.role = role
        self.listenAddress = listenAddress
        self.genesisHeader = genesisHeader
        self.secretKey = secretKey
        self.presistentStreamHandler = presistentStreamHandler
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
            presistentStreamHandler: options.presistentStreamHandler,
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
                    "connecting to peer", metadata: ["address": "\(address)", "role": "\(role)"]
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
        impl.connections.read { connections in
            connections.byPublicKey[publicKey]
        }
    }

    public func broadcast(
        kind: Handler.PresistentHandler.StreamKind, message: Handler.PresistentHandler.Message
    ) {
        let connections = impl.connections.read { connections in
            connections.byId.values
        }
        guard let messageData = try? message.encode() else {
            impl.logger.warning("Failed to encode message: \(message)")
            return
        }
        for connection in connections {
            if let stream = try? connection.createPreistentStream(kind: kind) {
                let res = Result(catching: { try stream.send(message: messageData) })
                switch res {
                case .success:
                    break
                case let .failure(error):
                    impl.logger.warning(
                        "Failed to send message",
                        metadata: [
                            "connectionId": "\(connection.id)",
                            "kind": "\(kind)",
                            "error": "\(error)",
                        ]
                    )
                }
            }
        }
    }

    // there should be only one connection per peer
    public var peersCount: Int {
        impl.connections.read { $0.byId.count }
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
    let presistentStreamHandler: Handler.PresistentHandler
    let ephemeralStreamHandler: Handler.EphemeralHandler

    fileprivate init(
        logger: Logger,
        role: PeerRole,
        settings: PeerSettings,
        alpns: [PeerRole: Data],
        publicKey: Data,
        clientConfiguration: QuicConfiguration,
        presistentStreamHandler: Handler.PresistentHandler,
        ephemeralStreamHandler: Handler.EphemeralHandler
    ) {
        self.logger = logger
        self.role = role
        self.settings = settings
        self.alpns = alpns
        self.publicKey = publicKey
        self.clientConfiguration = clientConfiguration
        self.presistentStreamHandler = presistentStreamHandler
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
                        self.logger.warning("Replacing least active builder connection at \(conn.remoteAddress)")
                        conn.close(abort: false)
                    } else {
                        self.logger.warning("Max builder connections reached, no eligible replacement found")
                        return false
                    }
                }
            }
            if connections.byAddr[addr] != nil {
                self.logger.warning("connection already exists")
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

        guard state.attempt < maxRetryAttempts else {
            logger.warning("reconnecting to \(address) exceeded max attempts")
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
                    logger.warning("reconnecting to \(address) already connected")
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
        var state = reopenStates.read { states in
            states[connection.id] ?? .init()
        }

        guard state.attempt < maxRetryAttempts else {
            logger.warning("Reopen attempt for stream \(kind) on connection \(connection.id) exceeded max attempts")
            return
        }
        state.applyBackoff()
        reopenStates.write { states in
            states[connection.id] = state
        }

        Task {
            try await Task.sleep(for: .seconds(state.delay))
            do {
                logger
                    .debug(
                        "Attempting to reopen UP stream of kind \(kind) for connection \(connection.id) attempt \(state.attempt) in \(state.delay) seconds"
                    )
                try connection.createPreistentStream(kind: kind)
            } catch {
                logger.error("Failed to reopen UP stream for connection \(connection.id): \(error)")
                reopenUpStream(connection: connection, kind: kind)
            }
        }
    }

    func addStream(_ stream: Stream<Handler>) {
        streams.write { streams in
            if streams[stream.id] != nil {
                self.logger.warning("stream already exists")
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
                "unknown alpn: \(String(data: info.negotiatedAlpn, encoding: .utf8) ?? info.negotiatedAlpn.toDebugHexString())"
            )
            return .code(.alpnNegFailure)
        }
        logger.debug("new connection: \(addr) role: \(role)")
        if impl.addConnection(connection, addr: addr, role: role) {
            return .code(.success)
        } else {
            return .code(.connectionRefused)
        }
    }

    func shouldOpen(_ connection: QuicConnection, certificate: Data?) -> QuicStatus {
        guard let certificate else {
            return .code(.requiredCert)
        }
        let conn = impl.connections.read { connections in
            connections.byId[connection.id]
        }
        guard let conn else {
            logger.warning(
                "Attempt to open but connection is absent",
                metadata: ["connectionId": "\(connection.id)"]
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
                ]
            )
            if publicKey == impl.publicKey {
                // Self connection detected
                logger.trace(
                    "Rejecting self-connection", metadata: ["connectionId": "\(connection.id)"]
                )
                return .code(.connectionRefused)
            }
            if alternativeName != generateSubjectAlternativeName(pubkey: publicKey) {
                return .code(.badCert)
            }
            // TODO: verify if it is current or next validator

            // Check for an existing connection by public key
            return try impl.connections.write { connections in
                if connections.byPublicKey.keys.contains(publicKey) {
                    // Deterministically decide based on public key comparison
                    if !publicKey.lexicographicallyPrecedes(impl.publicKey) {
                        connections.byPublicKey[publicKey] = conn
                        try conn.opened(publicKey: publicKey)
                        return .code(.success)
                    } else {
                        logger.debug(
                            "Rejecting duplicate connection by rule",
                            metadata: [
                                "connectionId": "\(connection.id)",
                                "publicKey": "\(publicKey.toHexString())",
                            ]
                        )
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
                metadata: ["connectionId": "\(connection.id)", "error": "\(error)"]
            )
            return .code(.badCert)
        }
    }

    func connected(_ connection: QuicConnection) {
        let conn = impl.connections.read { connections in
            connections.byId[connection.id]
        }
        guard let conn else {
            logger.warning("Connected but connection is gone?", metadata: ["connectionId": "\(connection.id)"])
            return
        }

        impl.reconnectStates.write { reconnectStates in
            reconnectStates[conn.remoteAddress] = nil
        }

        if conn.initiatedByLocal {
            for kind in Handler.PresistentHandler.StreamKind.allCases {
                do {
                    try conn.createPreistentStream(kind: kind)
                } catch {
                    logger.warning(
                        "\(connection.id) Failed to create presistent stream. Closing...",
                        metadata: ["kind": "\(kind)", "error": "\(error)"]
                    )
                    try? connection.shutdown(errorCode: 1) // TODO: define some error code
                    break
                }
            }
        }
    }

    func shutdownComplete(_ connection: QuicConnection) {
        logger.debug("connection shutdown complete", metadata: ["connectionId": "\(connection.id)"])
        let conn = impl.connections.read { connections in
            connections.byId[connection.id]
        }
        let needReconnect = impl.connections.write { connections in
            var needReconnect = false
            if let conn = connections.byId[connection.id] {
                needReconnect = conn.needReconnect
                if let publicKey = conn.publicKey {
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
                logger.error("reconnect failed", metadata: ["error": "\(error)"])
            }
        }
    }

    func shutdownInitiated(_ connection: QuicConnection, reason: ConnectionCloseReason) {
        logger.debug("Shutdown initiated", metadata: ["connectionId": "\(connection.id)", "reason": "\(reason)"])
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
            conn.streamStarted(stream: stream)
            // Check
            impl.reopenStates.write { states in
                states[conn.id] = nil
            }
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
        let stream = impl.streams.read { streams in
            streams[quicStream.id]
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
                    "Stream closed but connection is gone?", metadata: ["streamId": "\(stream.id)"]
                )
            }
        } else {
            logger.warning(
                "Stream closed but stream is gone?", metadata: ["streamId": "\(quicStream.id)"]
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
