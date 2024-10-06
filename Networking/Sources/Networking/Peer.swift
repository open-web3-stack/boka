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

// Define the Peer actor
public actor Peer {
    private let config: QuicConfig
    private var quicServer: QuicServer?
    private var clients: [NetAddr: QuicClient]
    private let eventBus: EventBus

    public init(config: QuicConfig, eventBus: EventBus) async throws {
        self.config = config
        self.eventBus = eventBus
        clients = [:]
        quicServer = try await QuicServer(config: config, messageHandler: self)
    }

    deinit {
        closeSync()
        peerLogger.info("Peer Deinit")
    }

    nonisolated func closeSync() {
        Task { [weak self] in
            await self?.close() // Using weak self to avoid retain cycle
        }
    }

    private func close() async {
        for client in clients.values {
            await client.close()
        }
        clients.removeAll()
        await quicServer?.close()
    }

    // Respond to a message with a specific messageID using Data
    func respond(to messageID: Int64, with data: Data) async -> QuicStatus {
        await quicServer?.respondGetStatus(to: messageID, with: data)
            ?? QuicStatusCode.internalError.rawValue
    }

    // Respond to a message with a specific messageID using PeerMessage
    func respond(to messageID: Int64, with message: any PeerMessage) async -> QuicStatus {
        let messageType = message.getMessageType()
        return await quicServer?
            .respondGetStatus(
                to: messageID,
                with: message.getData(),
                kind: (messageType == .uniquePersistent) ? .uniquePersistent : .commonEphemeral
            )
            ?? QuicStatusCode.internalError.rawValue
    }

    // Respond to a message with a specific messageID using PeerMessage (async throws)
    func respond(to messageID: Int64, with message: any PeerMessage) async throws {
        let messageType = message.getMessageType()
        let quicMessage = try await quicServer?.respondGetMessage(
            to: messageID, with: message.getData(),
            kind: (messageType == .uniquePersistent) ? .uniquePersistent : .commonEphemeral
        )
        if quicMessage?.type != .received {
            throw QuicError.sendFailed
        }
    }

    // Sends a message to another peer asynchronously
    func sendMessage(to peer: NetAddr, with message: any PeerMessage) async throws -> QuicMessage {
        let buffer = message.getData()
        let messageType = message.getMessageType()
        return try await sendDataToPeer(buffer, to: peer, messageType: messageType)
    }

    // Sends a message to another peer and returns the status
    func sendMessage(to peer: NetAddr, with message: any PeerMessage) async throws -> QuicStatus {
        let buffer = message.getData()
        let messageType = message.getMessageType()
        return try await sendDataToPeer(buffer, to: peer, messageType: messageType)
    }

    // send message to other peer wait for response quicMessage
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
            let client = try await QuicClient(config: config, messageHandler: self)
            clients[peerAddr] = client
            return try await client.send(
                message: data,
                streamKind: messageType == .uniquePersistent ? .uniquePersistent : .commonEphemeral
            )
        }
    }

    private func sendDataToPeer(_ data: Data, to peerAddr: NetAddr, messageType: PeerMessageType)
        async throws -> QuicStatus
    {
        if let client = clients[peerAddr] {
            // Client already exists, use it to send the data
            return try await client.send(
                data: data,
                streamKind: messageType == .uniquePersistent ? .uniquePersistent : .commonEphemeral
            )
        } else {
            let config = QuicConfig(
                id: config.id, cert: config.cert, key: config.key, alpn: config.alpn,
                ipAddress: peerAddr.ipAddress, port: peerAddr.port
            )
            // Client does not exist, create a new one
            let client = try await QuicClient(config: config, messageHandler: self)
            clients[peerAddr] = client
            return try await client.send(
                data: data,
                streamKind: messageType == .uniquePersistent ? .uniquePersistent : .commonEphemeral
            )
        }
    }

    private func removeClient(client: QuicClient) async {
        let peerAddr = await client.getNetAddr()
        await client.close()
        _ = clients.removeValue(forKey: peerAddr)
    }

    func getPeerAddr() -> String {
        "\(config.ipAddress):\(config.port)"
    }
}

// QuicClientMessageHandler methods
extension Peer: QuicClientMessageHandler {
    public func didReceiveMessage(quicClient: QuicClient, message: QuicMessage) {
        switch message.type {
        case .shutdownComplete:
            Task { [weak self] in
                guard let self else { return }
                await removeClient(client: quicClient)
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

// QuicServerMessageHandler methods
extension Peer: QuicServerMessageHandler {
    public func didReceiveMessage(messageID: Int64, message: QuicMessage) async {
        switch message.type {
        case .received:
            await eventBus.publish(PeerMessageReceived(messageID: messageID, message: message))
        case .shutdownComplete:
            break
        default:
            break
        }
    }

    public func didReceiveError(messageID: Int64, error: QuicError) {
        peerLogger.error("Failed to receive message: \(error)")
        Task {
            await eventBus.publish(PeerErrorReceived(messageID: messageID, error: error))
        }
    }
}
