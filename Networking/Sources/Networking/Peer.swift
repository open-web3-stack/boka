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

// TODO: reconnects, reopen UP stream, peer reputation system to ban peers not following the protocol
public final class Peer<Handler: StreamHandler>: Sendable {
    private let impl: PeerImpl<Handler>

    private let listener: QuicListener

    private var logger: Logger {
        impl.logger
    }

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
            registration: registration, pkcs12: pkcs12, alpns: allAlpns, client: false, settings: options.serverSettings
        )

        let clientAlpn = alpns[options.role]!
        let clientConfiguration = try QuicConfiguration(
            registration: registration, pkcs12: pkcs12, alpns: [clientAlpn], client: true, settings: options.clientSettings
        )

        impl = PeerImpl(
            logger: logger,
            role: options.role,
            settings: options.peerSettings,
            alpns: alpns,
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
    }

    public func listenAddress() throws -> NetAddr {
        try listener.listenAddress()
    }

    // TODO: see if we can remove the role parameter
    public func connect(to address: NetAddr, role: PeerRole) throws -> Connection<Handler> {
        let conn = impl.connections.read { connections in
            connections.byType[role]?[address]
        }
        return try conn ?? impl.connections.write { connections in
            let curr = connections.byType[role, default: [:]][address]
            if let curr {
                return curr
            }
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
            connections.byType[role, default: [:]][address] = conn
            connections.byId[conn.id] = conn
            return conn
        }
    }

    public func broadcast(kind: Handler.PresistentHandler.StreamKind, message: Handler.PresistentHandler.Message) {
        let connections = impl.connections.read { connections in
            connections.byId.values
        }

        guard let messageData = try? message.encode() else {
            impl.logger.warning("Failed to encode message: \(message)")
            return
        }
        for connection in connections {
            if let stream = try? connection.createPreistentStream(kind: kind) {
                let res = Result(catching: { try stream.send(data: messageData) })
                switch res {
                case .success:
                    break
                case let .failure(error):
                    impl.logger.warning("Failed to send message", metadata: [
                        "connectionId": "\(connection.id)",
                        "kind": "\(kind)",
                        "error": "\(error)",
                    ])
                }
            }
        }
    }

    // there should be only one connection per peer
    public func getPeersCount() -> Int {
        impl.connections.value.byId.values.count
    }
}

final class PeerImpl<Handler: StreamHandler>: Sendable {
    struct ConnectionStorage {
        var byType: [PeerRole: [NetAddr: Connection<Handler>]] = [:]
        var byId: [UniqueId: Connection<Handler>] = [:]
    }

    fileprivate let logger: Logger
    fileprivate let role: PeerRole
    fileprivate let settings: PeerSettings
    fileprivate let alpns: [PeerRole: Data]
    fileprivate let alpnLookup: [Data: PeerRole]

    fileprivate let clientConfiguration: QuicConfiguration

    fileprivate let connections: ThreadSafeContainer<ConnectionStorage> = .init(.init())
    fileprivate let streams: ThreadSafeContainer<[UniqueId: Stream<Handler>]> = .init([:])

    let presistentStreamHandler: Handler.PresistentHandler
    let ephemeralStreamHandler: Handler.EphemeralHandler

    fileprivate init(
        logger: Logger,
        role: PeerRole,
        settings: PeerSettings,
        alpns: [PeerRole: Data],
        clientConfiguration: QuicConfiguration,
        presistentStreamHandler: Handler.PresistentHandler,
        ephemeralStreamHandler: Handler.EphemeralHandler
    ) {
        self.logger = logger
        self.role = role
        self.settings = settings
        self.alpns = alpns
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
                let currentCount = connections.byType[role]?.count ?? 0
                if currentCount >= self.settings.maxBuilderConnections {
                    self.logger.warning("max builder connections reached")
                    // TODO: consider connection rotation strategy
                    return false
                }
            }
            if connections.byType[role, default: [:]][addr] != nil {
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
            connections.byType[role, default: [:]][addr] = conn
            connections.byId[connection.id] = conn
            return true
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

    func newConnection(_: QuicListener, connection: QuicConnection, info: ConnectionInfo) -> QuicStatus {
        let addr = info.remoteAddress
        let role = impl.alpnLookup[info.negotiatedAlpn]
        guard let role else {
            logger.warning("unknown alpn: \(String(data: info.negotiatedAlpn, encoding: .utf8) ?? info.negotiatedAlpn.toDebugHexString())")
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
        do {
            let (publicKey, alternativeName) = try parseCertificate(data: certificate, type: .x509)
            logger.trace("Certificate parsed", metadata: [
                "connectionId": "\(connection.id)",
                "publicKey": "\(publicKey.toHexString())",
                "alternativeName": "\(alternativeName)",
            ])
            if alternativeName != generateSubjectAlternativeName(pubkey: publicKey) {
                return .code(.badCert)
            }
            if impl.role == PeerRole.validator {
                // TODO: verify if it is current or next validator
            }
        } catch {
            logger.warning("Failed to parse certificate", metadata: [
                "connectionId": "\(connection.id)",
                "error": "\(error)"])
            return .code(.badCert)
        }
        return .code(.success)
    }

    func connected(_ connection: QuicConnection) {
        let conn = impl.connections.read { connections in
            connections.byId[connection.id]
        }
        guard let conn else {
            logger.warning("Connected but connection is gone?", metadata: ["connectionId": "\(connection.id)"])
            return
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
        logger.trace("connection shutdown complete", metadata: ["connectionId": "\(connection.id)"])
        impl.connections.write { connections in
            if let conn = connections.byId[connection.id] {
                connections.byId.removeValue(forKey: connection.id)
                connections.byType[conn.role]?.removeValue(forKey: conn.remoteAddress)
            }
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

    func dataReceived(_ stream: QuicStream, data: Data) {
        let stream = impl.streams.read { streams in
            streams[stream.id]
        }
        if let stream {
            stream.received(data: data)
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
            } else {
                logger.warning("Stream closed but connection is gone?", metadata: ["streamId": "\(stream.id)"])
            }
        } else {
            logger.warning("Stream closed but stream is gone?", metadata: ["streamId": "\(quicStream.id)"])
        }
    }
}
