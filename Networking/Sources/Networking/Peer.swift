import Foundation
import Logging

let peerLogger = Logger(label: "PeerServer")

public protocol PeerMessage: Equatable, Sendable {
    func getData() -> Data
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
        try quicServer?.start()
    }

    func close() throws {
        try quicServer?.close()
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
        let buffer = message.getData()
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
            let client = try QuicClient(config: config, messageHandler: self)
            let status = try client.start()
            if status.isFailed {
                throw QuicError.getClientFailed
            }
            clients[peerAddr] = client
            return try await client.send(message: data)
        }
    }

    func removeClient(with peerAddr: NetAddr) {
        _ = clients.removeValue(forKey: peerAddr)
    }

    func getPeerAddr() -> String {
        "\(config.ipAddress):\(config.port)"
    }

    deinit {
        peerLogger.info("Peer Deinit")
        // Clean up resources if necessary
    }
}

extension Peer: QuicClientMessageHandler {
    public func didReceiveMessage(quicClient: QuicClient, message: QuicMessage) {
        switch message.type {
        case .shutdownComplete:
            peerLogger.info("QuicClient shutdown complete")
            // Use [weak self] to avoid strong reference cycle
            DispatchQueue.main.async { [weak self] in
                self?.removeClient(with: quicClient.getNetAddr())
            }
        default:
            break
        }
    }

    public func didReceiveError(quicClient _: QuicClient, error: QuicError) {
        peerLogger.error("Failed to receive message: \(error)")
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
