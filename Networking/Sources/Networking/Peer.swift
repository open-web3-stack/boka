import Foundation
import Logging
import Utils

let peerLogger = Logger(label: "PeerServer")

public enum PeerMessageType: Sendable {
    case uniquePersistent // most messages type
    case commonEphemeral
}

public protocol PeerMessage: Equatable, Sendable {
    func getData() -> Data
    func getMessageType() -> PeerMessageType
}

public struct PeerMessageReceived: Event {
    public let messageID: String
    public let message: QuicMessage
}

// TODO: add error or remove it
public struct PeerErrorReceived: Event {
    public let messageID: String?
    public let error: QuicError
}

// Define the Peer actor
public actor Peer {
    private let config: QuicConfig
    private var quicServer: QuicServer!
    private var clients: [NetAddr: QuicClient]
    private let eventBus: EventBus

    public init(config: QuicConfig, eventBus: EventBus) async throws {
        self.config = config
        self.eventBus = eventBus
        clients = [:]
        quicServer = try await QuicServer(config: config, messageHandler: self)
    }

    deinit {
        Task { [weak self] in
            guard let self else { return }

            var clients = await self.clients
            for client in clients.values {
                await client.close()
            }
            clients.removeAll()
            await self.quicServer.close()
        }
    }

    // Respond to a message with a specific messageID using Data
    func respond(to messageID: String, with data: Data) async -> QuicStatus {
        await quicServer.respondGetStatus(to: messageID, with: data)
    }

    // Respond to a message with a specific messageID using PeerMessage
    func respond(to messageID: String, with message: any PeerMessage) async -> QuicStatus {
        let messageType = message.getMessageType()
        return
            await quicServer
                .respondGetStatus(
                    to: messageID,
                    with: message.getData(),
                    kind: (messageType == .uniquePersistent) ? .uniquePersistent : .commonEphemeral
                )
    }

    // Sends a message to another peer and returns the status
    func sendMessage(to peer: NetAddr, with message: any PeerMessage) async throws -> QuicStatus {
        let buffer = message.getData()
        let messageType = message.getMessageType()
        return try await sendDataToPeer(buffer, to: peer, messageType: messageType)
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
    public func didReceiveMessage(quicClient: QuicClient, message: QuicMessage) async {
        switch message.type {
        case .shutdownComplete:
            await removeClient(client: quicClient)
        default:
            break
        }
    }

    public func didReceiveError(quicClient _: QuicClient, error: QuicError) async {
        peerLogger.error("Failed to receive message: \(error)")
        await eventBus.publish(PeerErrorReceived(messageID: nil, error: error))
    }
}

// QuicServerMessageHandler methods
extension Peer: QuicServerMessageHandler {
    public func didReceiveMessage(server _: QuicServer, messageID: String, message: QuicMessage) async {
        switch message.type {
        case .received:
            await eventBus.publish(PeerMessageReceived(messageID: messageID, message: message))
        case .shutdownComplete:
            peerLogger.info("quic server shutdown")
        default:
            break
        }
    }

    public func didReceiveError(server _: QuicServer, messageID: String, error: QuicError) async {
        peerLogger.error("Failed to receive message: \(error)")
        await eventBus.publish(PeerErrorReceived(messageID: messageID, error: error))
    }
}