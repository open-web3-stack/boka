import Foundation

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

// Define the Peer class
public final class Peer: @unchecked Sendable, QuicServerDelegate {
    private let config: QuicConfig
    private var quicServer: QuicServer?
    public var onMessageReceived: ((Int64, Result<QuicMessage, QuicError>) -> Void)?

    public init(config: QuicConfig) throws {
        self.config = config
        quicServer = try QuicServer(config: config)
        quicServer?.delegate = self
    }

    func start() throws {
        // Implement start logic
        try quicServer?.start()
//        quicServer?.onMessageReceived = onMessageReceived
    }

    func close() throws {
        // Implement close logic
    }

    public func didReceiveMessage(
        quicServer _: QuicServer, messageID: Int64, result: Result<QuicMessage, QuicError>
    ) {
        onMessageReceived?(messageID, result)
    }

    public func getPeerAddr() -> String {
        "\(config.ipAddress):\(config.port)"
    }

    deinit {
        // Clean up resources if necessary
    }
}
