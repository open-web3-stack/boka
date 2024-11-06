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

struct ReconnectState {
    var attempt: Int
    var delay: TimeInterval

    init() {
        attempt = 0
        delay = 1
    }

    // Initializer with custom values
    init(attempt: Int = 0, delay: TimeInterval = 1) {
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

// TODO: reopen UP stream, peer reputation system to ban peers not following the protocol
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
    fileprivate let reconnectStates: ThreadSafeContainer<[NetAddr: ReconnectState]> = .init([:])

    let reconnectMaxRetryAttempts = 5
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
                    self.logger.warning("max builder connections reached")
                    // TODO: consider connection rotation strategy
                    return false
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
        let state = reconnectStates.read { reconnectStates in
            reconnectStates[address] ?? .init()
        }
        if state.attempt < reconnectMaxRetryAttempts {
            reconnectStates.write { reconnectStates in
                if var state = reconnectStates[address] {
                    state.applyBackoff()
                    reconnectStates[address] = state
                }
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
        } else {
            logger.warning("reconnect attempt exceeded max attempts")
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
            logger.warning(
                "Connected but connection is gone?", metadata: ["connectionId": "\(connection.id)"]
            )
            return
        }
        // Check if the connection is already reconnected
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
            if let conn = connections.byId[connection.id] {
                let needReconnect = conn.needReconnect
                if let publicKey = conn.publicKey {
                    connections.byPublicKey.removeValue(forKey: publicKey)
                }
                connections.byId.removeValue(forKey: connection.id)
                connections.byAddr.removeValue(forKey: conn.remoteAddress)
                conn.closed()
                return needReconnect
            }
            return false
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
        logger.debug(
            "Shutdown initiated",
            metadata: ["connectionId": "\(connection.id)", "reason": "\(reason)"]
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
            case .badCert:
                false
            default:
                !status.isSucceeded
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
        }
    }

    func dataReceived(_ stream: QuicStream, data: Data?) {
        let stream = impl.streams.read { streams in
            streams[stream.id]
        }
        if let stream {
            stream.received(data: data)
        }
    }

    func closed(_ quicStream: QuicStream, status: QuicStatus, code: QuicErrorCode) {
        let stream = impl.streams.read { streams in
            streams[quicStream.id]
        }
        logger.info("closed stream \(String(describing: stream?.id)) \(status) \(code)")

        if let stream {
            let connection = impl.connections.read { connections in
                connections.byId[stream.connectionId]
            }
            if let connection {
                connection.streamClosed(stream: stream, abort: !status.isSucceeded)
                if shouldReopenStream(connection: connection, stream: stream, status: status) {
                    do {
                        if let kind = stream.kind {
                            do {
                                try connection.createPreistentStream(kind: kind)
                            } catch {
                                logger.error("Attempt to recreate the persistent stream failed: \(error)")
                            }
                        }
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

    private func shouldReopenStream(connection: Connection<Handler>, stream: Stream<Handler>, status: QuicStatus) -> Bool {
        logger.info("reopen stream about connection needReconnect:\(connection.needReconnect) isClosed:\(connection.isClosed)")
        // Need to reopen connection or close it
        if connection.needReconnect || connection.isClosed {
            return false
        }
        // Only reopen if the stream is a persistent UP stream and the closure was unexpected
        return stream.kind != nil && status.rawValue != QuicStatusCode.connectionIdle.rawValue
    }
}
