import Foundation
import Logging
import MsQuicSwift
import Utils

public typealias NetAddr = MsQuicSwift.NetAddr

public enum StreamType: Sendable {
    case uniquePersistent
    case commonEphemeral
}

public enum PeerMode: Sendable, Hashable {
    case validator
    case builder
    // case proxy // not yet specified
}

public struct PeerOptions<Handler: StreamHandler>: Sendable {
    public var mode: PeerMode
    public var listenAddress: NetAddr
    public var genesisHeader: Data32
    public var secretKey: Ed25519.SecretKey
    public var presistentStreamHandler: Handler.PresistentHandler
    public var ephemeralStreamHandler: Handler.EphemeralHandler
    public var serverSettings: QuicSettings
    public var clientSettings: QuicSettings
    public var peerSettings: PeerSettings

    public init(
        mode: PeerMode,
        listenAddress: NetAddr,
        genesisHeader: Data32,
        secretKey: Ed25519.SecretKey,
        presistentStreamHandler: Handler.PresistentHandler,
        ephemeralStreamHandler: Handler.EphemeralHandler,
        serverSettings: QuicSettings = .defaultSettings,
        clientSettings: QuicSettings = .defaultSettings,
        peerSettings: PeerSettings = .defaultSettings
    ) {
        self.mode = mode
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
            PeerMode.validator: Alpn(genesisHeader: options.genesisHeader, builder: false).data,
            PeerMode.builder: Alpn(genesisHeader: options.genesisHeader, builder: true).data,
        ]
        let allAlpns = Array(alpns.values)

        let pkcs12 = try generateSelfSignedCertificate(privateKey: options.secretKey)

        let registration = try QuicRegistration()
        let serverConfiguration = try QuicConfiguration(
            registration: registration, pkcs12: pkcs12, alpns: allAlpns, client: false, settings: options.serverSettings
        )

        let clientAlpn = alpns[options.mode]!
        let clientConfiguration = try QuicConfiguration(
            registration: registration, pkcs12: pkcs12, alpns: [clientAlpn], client: true, settings: options.clientSettings
        )

        impl = PeerImpl(
            logger: logger,
            mode: options.mode,
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

    public func connect(to address: NetAddr, mode: PeerMode) throws -> Connection<Handler> {
        let conn = impl.connections.read { connections in
            connections.byType[mode]?[address]
        }
        return try conn ?? impl.connections.write { connections in
            let curr = connections.byType[mode, default: [:]][address]
            if let curr {
                return curr
            }
            let conn = try Connection(
                QuicConnection(
                    handler: PeerEventHandler(self.impl),
                    registration: self.impl.clientConfiguration.registration,
                    configuration: self.impl.clientConfiguration
                ),
                impl: self.impl,
                mode: mode,
                remoteAddress: address,
                initiatedByLocal: true
            )
            connections.byType[mode, default: [:]][address] = conn
            connections.byId[conn.id] = conn
            return conn
        }
    }
}

final class PeerImpl<Handler: StreamHandler>: Sendable {
    struct ConnectionStorage {
        var byType: [PeerMode: [NetAddr: Connection<Handler>]] = [:]
        var byId: [UniqueId: Connection<Handler>] = [:]
    }

    fileprivate let logger: Logger
    fileprivate let mode: PeerMode
    fileprivate let settings: PeerSettings
    fileprivate let alpns: [PeerMode: Data]
    fileprivate let alpnLookup: [Data: PeerMode]

    fileprivate let clientConfiguration: QuicConfiguration

    fileprivate let connections: ThreadSafeContainer<ConnectionStorage> = .init(.init())
    fileprivate let streams: ThreadSafeContainer<[UniqueId: Stream<Handler>]> = .init([:])

    let presistentStreamHandler: Handler.PresistentHandler
    let ephemeralStreamHandler: Handler.EphemeralHandler

    fileprivate init(
        logger: Logger,
        mode: PeerMode,
        settings: PeerSettings,
        alpns: [PeerMode: Data],
        clientConfiguration: QuicConfiguration,
        presistentStreamHandler: Handler.PresistentHandler,
        ephemeralStreamHandler: Handler.EphemeralHandler
    ) {
        self.logger = logger
        self.mode = mode
        self.settings = settings
        self.alpns = alpns
        self.clientConfiguration = clientConfiguration
        self.presistentStreamHandler = presistentStreamHandler
        self.ephemeralStreamHandler = ephemeralStreamHandler

        var alpnLookup = [Data: PeerMode]()
        for (mode, alpn) in alpns {
            alpnLookup[alpn] = mode
        }
        self.alpnLookup = alpnLookup
    }

    func addConnection(_ connection: QuicConnection, addr: NetAddr, mode: PeerMode) -> Bool {
        connections.write { connections in
            if mode == .builder {
                let currentCount = connections.byType[mode]?.count ?? 0
                if currentCount >= self.settings.maxBuilderConnections {
                    self.logger.warning("max builder connections reached")
                    // TODO: consider connection rotation strategy
                    return false
                }
            }
            if connections.byType[mode, default: [:]][addr] != nil {
                self.logger.warning("connection already exists")
                return false
            }
            let conn = Connection(
                connection,
                impl: self,
                mode: mode,
                remoteAddress: addr,
                initiatedByLocal: false
            )
            connections.byType[mode, default: [:]][addr] = conn
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
        let mode = impl.alpnLookup[info.negotiatedAlpn]
        guard let mode else {
            logger.warning("unknown alpn: \(String(data: info.negotiatedAlpn, encoding: .utf8) ?? info.negotiatedAlpn.toDebugHexString())")
            return .code(.alpnNegFailure)
        }
        logger.debug("new connection: \(addr) mode: \(mode)")
        if impl.addConnection(connection, addr: addr, mode: mode) {
            return .code(.success)
        } else {
            return .code(.connectionRefused)
        }
    }

    func shouldOpen(_: QuicConnection, certificate _: Data?) -> QuicStatus {
        // TODO: verify certificate
        // - Require a certificate
        // - Verify the alt name matches to the public key
        // - Check connection mode and if validator, verify if it is current or next validator
        .code(.success)
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

    func shutdownInitiated(_ connection: QuicConnection, reason _: ConnectionCloseReason) {
        impl.connections.write { connections in
            if let conn = connections.byId[connection.id] {
                connections.byId.removeValue(forKey: connection.id)
                connections.byType[conn.mode]?.removeValue(forKey: conn.remoteAddress)
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
