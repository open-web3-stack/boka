import Foundation
import Logging
import Utils

// Logger for Peer
let peerLogger = Logger(label: "PeerServer")

// Define message types
public enum PeerMessageType: Sendable {
    case uniquePersistent
    case commonEphemeral
    case unknown
}

// Define PeerMessage protocol
public protocol PeerMessage: Equatable, Sendable {
    func getData() -> Data
    func getMessageType() -> PeerMessageType
}

extension PeerMessage {
    public func getMessageType() -> PeerMessageType {
        .uniquePersistent
    }
}

// Define events
public struct PeerMessageReceived: Event {
    public let messageID: Int64
    public let message: QuicMessage
}

// TODO: add error or remove it
public struct PeerErrorReceived: Event {
    public let messageID: Int64?
    public let error: QuicError
}

// Define the Peer class
public final class Peer: @unchecked Sendable {
    private let config: QuicConfig
    private var quicServer: QuicServer?
    private var clients: AtomicDictionary<NetAddr, QuicClient>
    private let eventBus: EventBus

    public init(config: QuicConfig, eventBus: EventBus) throws {
        self.config = config
        self.eventBus = eventBus
        clients = .init()
        quicServer = try QuicServer(config: config, messageHandler: self)
    }

    func start() throws {
        try quicServer?.start()
    }

    func close() {
        quicServer?.close()
    }

    // reply messsage to other peer
    func replyTo(messageID: Int64, with data: Data) async throws {
        try await quicServer?.replyTo(messageID: messageID, with: data)
    }

    // reply messsage to other peer
    func replyTo(messageID: Int64, with data: Data) -> QuicStatus {
        quicServer?.replyTo(messageID: messageID, with: data)
            ?? QuicStatusCode.internalError.rawValue
    }

    // reply messsage to other peer
    func replyTo(messageID: Int64, with message: any PeerMessage) async throws {
        try await quicServer?.replyTo(messageID: messageID, with: message.getData())
    }

    // send message to other peer
    func sendMessageToPeer(
        message: any PeerMessage, peerAddr: NetAddr
    ) async throws -> QuicMessage {
        let buffer = message.getData()
        let messageType = message.getMessageType()
        return try await sendDataToPeer(buffer, to: peerAddr, messageType: messageType)
    }

    private func sendDataToPeer(_ data: Data, to peerAddr: NetAddr, messageType: PeerMessageType)
        async throws -> QuicMessage
    {
        if let client = clients[peerAddr] {
            // Client already exists, use it to send the data
            return try await client.send(
                message: data,
                streamKind: messageType == .uniquePersistent ? .uniquePersistent : .commonEphemeral
            )
        } else {
            let config = QuicConfig(
                id: config.id, cert: config.cert, key: config.key, alpn: config.alpn,
                ipAddress: peerAddr.ipAddress, port: peerAddr.port
            )
            // Client does not exist, create a new one
            let client = try QuicClient(config: config, messageHandler: self)
            let status = try client.start()
            if status.isFailed {
                throw QuicError.getClientFailed
            }
            clients[peerAddr] = client
            return try await client.send(
                message: data,
                streamKind: messageType == .uniquePersistent ? .uniquePersistent : .commonEphemeral
            )
        }
    }

    private func removeClient(with peerAddr: NetAddr) {
        _ = clients.removeValue(forKey: peerAddr)
    }

    func getPeerAddr() -> String {
        "\(config.ipAddress):\(config.port)"
    }

    // TODO: add more functions for peer
    deinit {
        clients.removeAll()
        quicServer?.close()
        peerLogger.info("Peer Deinit")
        // Clean up resources if necessary
    }
}

extension Peer: QuicClientMessageHandler {
    public func didReceiveMessage(quicClient: QuicClient, message: QuicMessage) {
        switch message.type {
        case .close:
            peerLogger.info("QuicClient close")
            // Use Task to avoid strong reference cycle
            Task { [weak self] in
                guard let self else { return }
                removeClient(with: quicClient.getNetAddr())
            }
        default:
            break
        }
    }

    public func didReceiveError(quicClient _: QuicClient, error: QuicError) {
        peerLogger.error("Failed to receive message: \(error)")
        Task {
            await eventBus.publish(PeerErrorReceived(messageID: nil, error: error))
        }
    }
}

extension Peer: QuicServerMessageHandler {
    public func didReceiveMessage(quicServer _: QuicServer, messageID: Int64, message: QuicMessage) {
        switch message.type {
        case .received:
            Task {
                await eventBus.publish(PeerMessageReceived(messageID: messageID, message: message))
            }
        case .shutdownComplete:
            break
        default:
            break
        }
    }

    public func didReceiveError(quicServer _: QuicServer, messageID: Int64, error: QuicError) {
        peerLogger.error("Failed to receive message: \(error)")
        Task {
            await eventBus.publish(PeerErrorReceived(messageID: messageID, error: error))
        }
    }
}
