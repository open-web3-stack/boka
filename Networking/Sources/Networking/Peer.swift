import Foundation
import Logging
import MsQuicSwift
import Utils

private let logger = Logger(label: "PeerServer")

public enum StreamType: Sendable {
    case uniquePersistent
    case commonEphemeral
}

public protocol Message {
    func encode() -> Data
}

public struct PeerConfiguration: Sendable {
    public var listenAddress: NetAddr
    public var alpn: Alpn
    public var pkcs12: Data
    public var settings: QuicSettings

    public init(listenAddress: NetAddr, alpn: Alpn, pkcs12: Data, settings: QuicSettings = .defaultSettings) {
        self.listenAddress = listenAddress
        self.alpn = alpn
        self.pkcs12 = pkcs12
        self.settings = settings
    }
}

// TODO: implement a connection pool that is able to:
// - distinguish connection types (e.g. validators, work package builders)
// - limit max connections per connection type
// - manage peer reputation and rotate connections when full
public final class Peer: Sendable {
    private let config: PeerConfiguration
    private let eventBus: EventBus
    private let listener: QuicListener
    private let connections: ThreadSafeContainer<[NetAddr: QuicConnection]> = .init([:])
    private let streams: ThreadSafeContainer<[NetAddr: [QuicStream]]> = .init([:])

    public var events: some Subscribable {
        eventBus
    }

    public init(config: PeerConfiguration, eventBus: EventBus) async throws {
        self.config = config
        self.eventBus = eventBus

        let registration = try QuicRegistration()
        let configuration = try QuicConfiguration(
            registration: registration, pkcs12: config.pkcs12, alpn: config.alpn.data, client: false, settings: config.settings
        )

        listener = try QuicListener(
            handler: PeerEventHandler(),
            registration: registration,
            configuration: configuration,
            listenAddress: config.listenAddress,
            alpn: config.alpn.data
        )
    }
}

public final class PeerEventHandler: QuicEventHandler {}
