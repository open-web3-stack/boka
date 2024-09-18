import Foundation
import Logging

let peerLogger = Logger(label: "PeerServer")

public protocol PeerMessage: Equatable, Sendable {
    var timestamp: Int { get }
    var type: MessageType { get }
    var data: Data { get }
    init(type: MessageType, data: Data)
}

public enum MessageType: Int, Sendable {
    case text = 0
    case hello = 1
    case block = 2
    case transaction = 3
}

public protocol PeerMessageHandler: AnyObject {
    func didReceivePeerMessage(peer: Peer, messageID: Int64, message: QuicMessage)
    func didReceivePeerError(peer: Peer, messageID: Int64, error: QuicError)
}

// Define the Peer class
public final class Peer: @unchecked Sendable {
    private let config: QuicConfig
    private var quicServer: QuicServer?
    private var clients: AtomicDictionary<NetAddr, QuicClient>
    private weak var messageHandler: PeerMessageHandler?
    public init(config: QuicConfig, messageHandler: PeerMessageHandler? = nil) throws {
        self.config = config
        self.messageHandler = messageHandler
        clients = .init()
        quicServer = try QuicServer(config: config, messageHandler: self)
    }

    func start() throws {
        // Implement start logic
        try quicServer?.start()
    }

    func close() throws {
        // Implement close logic
    }

    func replyTo(messageID: Int64, with data: Data) async throws {
        try await quicServer?.replyTo(messageID: messageID, with: data)
    }

    func replyTo(messageID: Int64, with data: Data) -> QuicStatus {
        quicServer?.replyTo(messageID: messageID, with: data) ?? QuicStatusCode.internalError.rawValue
    }

    func sendMessageToPeer(
        message: any PeerMessage, peerAddr: NetAddr
    ) async throws -> QuicMessage {
        let buffer = Data(message.data)
        return try await sendDataToPeer(buffer, to: peerAddr)
    }

    func sendDataToPeer(_ data: Data, to peerAddr: NetAddr) async throws -> QuicMessage {
        if let client = clients[peerAddr] {
            // Client already exists, use it to send the data
            return try await client.send(message: data)
        } else {
            let config = QuicConfig(
                id: config.id, cert: config.cert, key: config.key, alpn: config.alpn,
                ipAddress: peerAddr.ipAddress, port: peerAddr.port
            )
            // Client does not exist, create a new one
            let client = try QuicClient(config: config)
            let status = try client.start()
            if status.isFailed {
                throw QuicError.getClientFailed
            }
            clients[peerAddr] = client
            return try await client.send(message: data)
        }
    }

    func getPeerAddr() -> String {
        "\(config.ipAddress):\(config.port)"
    }

    deinit {
        // Clean up resources if necessary
    }
}

extension Peer: QuicServerMessageHandler {
    public func didReceiveMessage(quicServer _: QuicServer, messageID: Int64, message: QuicMessage) {
        switch message.type {
        case .received:
            messageHandler?.didReceivePeerMessage(peer: self, messageID: messageID, message: message)
        case .shutdownComplete:
            break
        default:
            break
        }
    }

    public func didReceiveError(quicServer _: QuicServer, messageID _: Int64, error: QuicError) {
        peerLogger.error("Failed to receive message: \(error)")
    }
}
