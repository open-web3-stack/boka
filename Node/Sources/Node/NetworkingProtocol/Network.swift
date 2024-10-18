import Blockchain
import Foundation
import Networking
import TracingUtils
import Utils

public final class Network: Sendable {
    public struct Config {
        public var protocolConfig: ProtocolConfigRef
        public var mode: PeerMode
        public var listenAddress: NetAddr
        public var genesisHeader: Data32
        public var peerSettings: PeerSettings
    }

    private let impl: NetworkImpl
    private let peer: Peer<HandlerDef>

    public init(
        config: Config,
        key: Ed25519.SecretKey,
        eventBus: EventBus
    ) throws {
        let logger = Logger(label: "Network".uniqueId)

        impl = NetworkImpl(
            logger: logger,
            eventBus: eventBus,
            config: config.protocolConfig
        )

        let option = PeerOptions<HandlerDef>(
            mode: config.mode,
            listenAddress: config.listenAddress,
            genesisHeader: config.genesisHeader,
            secretKey: key,
            presistentStreamHandler: PresistentStreamHandlerImpl(impl: impl),
            ephemeralStreamHandler: EphemeralStreamHandlerImpl(impl: impl),
            serverSettings: .defaultSettings,
            clientSettings: .defaultSettings
        )

        peer = try Peer(options: option)
    }

    public func connect(to: NetAddr, mode: PeerMode) throws -> some ConnectionInfoProtocol {
        try peer.connect(to: to, mode: mode)
    }
}

struct HandlerDef: StreamHandler {
    typealias PresistentHandler = PresistentStreamHandlerImpl
    typealias EphemeralHandler = EphemeralStreamHandlerImpl
}

private final class NetworkImpl: Sendable {
    fileprivate let logger: Logger
    fileprivate let eventBus: EventBus
    fileprivate let config: ProtocolConfigRef

    init(logger: Logger, eventBus: EventBus, config: ProtocolConfigRef) {
        self.logger = logger
        self.eventBus = eventBus
        self.config = config
    }
}

struct PresistentStreamHandlerImpl: PresistentStreamHandler {
    typealias StreamKind = UniquePresistentStreamKind
    typealias Message = Data // TODO: use real type

    fileprivate let impl: NetworkImpl

    func createDecoder(kind _: StreamKind,
                       onResult _: @escaping @Sendable (Result<Message, Error>) -> Void) -> any MessageDecoder<Message>
    {
        fatalError("unimplemented")
    }

    func streamOpened(connection _: any ConnectionInfoProtocol, stream _: any StreamProtocol, kind _: StreamKind) throws {
        // TODO: send handshake
    }

    func handle(connection _: any ConnectionInfoProtocol, message _: Message) throws {
        // TODO: publish to event bus
    }
}

typealias RequestDisambiguated = Request

struct EphemeralStreamHandlerImpl: EphemeralStreamHandler {
    typealias StreamKind = CommonEphemeralStreamKind
    typealias Request = RequestDisambiguated

    fileprivate let impl: NetworkImpl

    func createDecoder(kind: StreamKind, onResult: @escaping @Sendable (Result<Request, Error>) -> Void) -> any MessageDecoder<Request> {
        RequestMessageDecoder(config: impl.config, kind: kind, onResult: onResult)
    }

    func handle(connection: any ConnectionInfoProtocol, request: Request) async throws -> Data {
        impl.logger.debug("handling request: \(request) from \(connection.id)")
        return Data()
    }
}
