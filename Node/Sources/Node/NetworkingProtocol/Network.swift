import Blockchain
import Codec
import Foundation
import Networking
import TracingUtils
import Utils

public protocol NetworkProtocolHandler: Sendable {
    func handle(ceRequest: CERequest) async throws -> (any Encodable)?
    func handle(connection: some ConnectionInfoProtocol, upMessage: UPMessage) async throws

    func handle(
        connection: some ConnectionInfoProtocol,
        stream: some StreamProtocol<UPMessage>,
        kind: UniquePresistentStreamKind
    ) async throws
}

public final class Network: Sendable {
    public struct Config {
        public var role: PeerRole
        public var listenAddress: NetAddr
        public var key: Ed25519.SecretKey
        public var peerSettings: PeerSettings

        public init(
            role: PeerRole,
            listenAddress: NetAddr,
            key: Ed25519.SecretKey,
            peerSettings: PeerSettings = .defaultSettings
        ) {
            self.role = role
            self.listenAddress = listenAddress
            self.key = key
            self.peerSettings = peerSettings
        }
    }

    private let impl: NetworkImpl
    private let peer: Peer<HandlerDef>

    public init(
        config: Config,
        protocolConfig: ProtocolConfigRef,
        genesisHeader: Data32,
        handler: NetworkProtocolHandler
    ) throws {
        let logger = Logger(label: "Network".uniqueId)

        impl = NetworkImpl(
            logger: logger,
            config: protocolConfig,
            handler: handler
        )

        let option = PeerOptions<HandlerDef>(
            role: config.role,
            listenAddress: config.listenAddress,
            genesisHeader: genesisHeader,
            secretKey: config.key,
            presistentStreamHandler: PresistentStreamHandlerImpl(impl: impl),
            ephemeralStreamHandler: EphemeralStreamHandlerImpl(impl: impl),
            serverSettings: .defaultSettings,
            clientSettings: .defaultSettings
        )

        peer = try Peer(options: option)
    }

    public func connect(to: NetAddr, role: PeerRole) throws -> some ConnectionInfoProtocol {
        try peer.connect(to: to, role: role)
    }

    public func send(to: NetAddr, message: CERequest) async throws -> Data {
        let conn = try peer.connect(to: to, role: .builder)
        return try await conn.request(message)
    }

    public func broadcast(kind: UniquePresistentStreamKind, message: UPMessage) {
        peer.broadcast(kind: kind, message: message)
    }

    public func listenAddress() throws -> NetAddr {
        try peer.listenAddress()
    }
}

struct HandlerDef: StreamHandler {
    typealias PresistentHandler = PresistentStreamHandlerImpl
    typealias EphemeralHandler = EphemeralStreamHandlerImpl
}

private final class NetworkImpl: Sendable {
    let logger: Logger
    let config: ProtocolConfigRef
    let handler: NetworkProtocolHandler

    init(logger: Logger, config: ProtocolConfigRef, handler: NetworkProtocolHandler) {
        self.logger = logger
        self.config = config
        self.handler = handler
    }
}

struct PresistentStreamHandlerImpl: PresistentStreamHandler {
    typealias StreamKind = UniquePresistentStreamKind
    typealias Message = UPMessage

    fileprivate let impl: NetworkImpl

    func createDecoder(kind: StreamKind) -> any MessageDecoder<Message> {
        switch kind {
        case .blockAnnouncement:
            BlockAnnouncementDecoder(config: impl.config, kind: kind)
        }
    }

    func streamOpened(connection: any ConnectionInfoProtocol, stream: any StreamProtocol<Message>, kind: StreamKind) async throws {
        try await impl.handler.handle(connection: connection, stream: stream, kind: kind)
    }

    func handle(connection: any ConnectionInfoProtocol, message: Message) async throws {
        impl.logger.trace("handling message: \(message) from \(connection.id)")

        try await impl.handler.handle(connection: connection, upMessage: message)
    }
}

struct EphemeralStreamHandlerImpl: EphemeralStreamHandler {
    typealias StreamKind = CommonEphemeralStreamKind
    typealias Request = CERequest

    fileprivate let impl: NetworkImpl

    func createDecoder(kind: StreamKind) -> any MessageDecoder<Request> {
        CEMessageDecoder(config: impl.config, kind: kind)
    }

    func handle(connection: any ConnectionInfoProtocol, request: Request) async throws -> Data {
        impl.logger.trace("handling request: \(request) from \(connection.id)")
        let resp = try await impl.handler.handle(ceRequest: request)
        if let resp {
            return try JamEncoder.encode(resp)
        }
        return Data()
    }
}
