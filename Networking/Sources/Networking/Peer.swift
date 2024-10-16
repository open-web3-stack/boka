import Foundation
import Logging
import MsQuicSwift
import Utils

public enum StreamType: Sendable {
    case uniquePersistent
    case commonEphemeral
}

public enum PeerMode: Sendable, Hashable {
    case validator
    case builder
    // case proxy // not yet specified
}

public protocol Message {
    func encode() -> Data
}

public struct PeerOptions: Sendable {
    public var mode: PeerMode
    public var listenAddress: NetAddr
    public var genesisHeader: Data32
    public var secretKey: Ed25519.SecretKey
    public var serverSettings: QuicSettings
    public var clientSettings: QuicSettings
    public var peerSettings: PeerSettings

    public init(
        mode: PeerMode,
        listenAddress: NetAddr,
        genesisHeader: Data32,
        secretKey: Ed25519.SecretKey,
        serverSettings: QuicSettings = .defaultSettings,
        clientSettings: QuicSettings = .defaultSettings,
        peerSettings: PeerSettings = .defaultSettings
    ) {
        self.mode = mode
        self.listenAddress = listenAddress
        self.genesisHeader = genesisHeader
        self.secretKey = secretKey
        self.serverSettings = serverSettings
        self.clientSettings = clientSettings
        self.peerSettings = peerSettings
    }
}

// TODO: implement a connection pool that is able to:
// - distinguish connection types (e.g. validators, work package builders)
// - limit max connections per connection type
// - manage peer reputation and rotate connections when full
public final class Peer: Sendable {
    private let impl: PeerImpl

    private let listener: QuicListener

    public var events: some Subscribable {
        impl.eventBus
    }

    private var logger: Logger {
        impl.logger
    }

    public init(options: PeerOptions, eventBus: EventBus) throws {
        let logger = Logger(label: "Peer".uniqueId)
        let eventBus = eventBus

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
            eventBus: eventBus,
            mode: options.mode,
            settings: options.peerSettings,
            alpns: alpns,
            clientConfiguration: clientConfiguration
        )

        listener = try QuicListener(
            handler: PeerEventHandler(impl),
            registration: registration,
            configuration: serverConfiguration,
            listenAddress: options.listenAddress,
            alpns: allAlpns
        )
    }

    public func connect(to address: NetAddr, mode: PeerMode) throws -> Connection {
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
                remoteAddress: address
            )
            connections.byType[mode, default: [:]][address] = conn
            connections.byId[conn.connection] = conn
            return conn
        }
    }
}

struct ConnectionStorage {
    var byType: [PeerMode: [NetAddr: Connection]] = [:]
    var byId: [QuicConnection: Connection] = [:]
}

final class PeerImpl: Sendable {
    fileprivate let logger: Logger
    fileprivate let eventBus: EventBus
    fileprivate let mode: PeerMode
    fileprivate let settings: PeerSettings
    fileprivate let alpns: [PeerMode: Data]
    fileprivate let alpnLookup: [Data: PeerMode]

    fileprivate let clientConfiguration: QuicConfiguration

    fileprivate let connections: ThreadSafeContainer<ConnectionStorage> = .init(.init())
    fileprivate let streams: ThreadSafeContainer<[QuicStream: Stream]> = .init([:])

    init(
        logger: Logger,
        eventBus: EventBus,
        mode: PeerMode,
        settings: PeerSettings,
        alpns: [PeerMode: Data],
        clientConfiguration: QuicConfiguration
    ) {
        self.logger = logger
        self.eventBus = eventBus
        self.mode = mode
        self.settings = settings
        self.alpns = alpns
        self.clientConfiguration = clientConfiguration

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
            let conn = Connection(connection, impl: self, mode: mode, remoteAddress: addr)
            connections.byType[mode, default: [:]][addr] = conn
            connections.byId[connection] = conn
            return true
        }
    }

    func addStream(_ stream: Stream) {
        streams.write { streams in
            if streams[stream.stream] != nil {
                self.logger.warning("stream already exists")
            }
            streams[stream.stream] = stream
        }
    }
}

private final class PeerEventHandler: QuicEventHandler {
    private let impl: PeerImpl

    private var logger: Logger {
        impl.logger
    }

    init(_ impl: PeerImpl) {
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

    func connected(_: QuicConnection) {}

    func shutdownInitiated(_ connection: QuicConnection, reason _: ConnectionCloseReason) {
        impl.connections.write { connections in
            if let conn = connections.byId[connection] {
                connections.byId.removeValue(forKey: connection)
                connections.byType[conn.mode]?.removeValue(forKey: conn.remoteAddress)
            }
        }
    }

    func streamStarted(_ connection: QuicConnection, stream: QuicStream) {
        let conn = impl.connections.read { connections in
            connections.byId[connection]
        }
        if let conn {
            conn.streamStarted(stream: stream)
        }
    }

    func dataReceived(_ stream: QuicStream, data: Data) {
        let stream = impl.streams.read { streams in
            streams[stream]
        }
        if let stream {
            stream.received(data: data)
        }
    }

    func closed(_ stream: QuicStream, status: QuicStatus, code _: QuicErrorCode) {
        let stream = impl.streams.read { streams in
            streams[stream]
        }
        if let stream {
            if status.isSucceeded {
                stream.close()
            } else {
                stream.abort()
            }
        }
    }
}
