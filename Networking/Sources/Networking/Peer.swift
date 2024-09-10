import Foundation

public enum MessageType: Int, Sendable {
    case text = 0
    case hello = 1
    case block = 2
    case transaction = 3
}

public struct Message: Equatable, Sendable {
    public let id: Int
    public let type: MessageType
    public let data: Data
    public init(_ type: MessageType = .text, data: Data) {
        id = Int(Date().timeIntervalSince1970 * 1000)
        self.type = type
        self.data = data
    }
}

// Define the Peer class
public final class Peer: @unchecked Sendable {
    private let config: QuicConfig
    private var quicServer: QuicServer?
    public var onDataReceived: ((Data) -> Void)?
    private let callbackQueue: DispatchQueue
    private let messageQueue: DispatchQueue

    public init(config: QuicConfig) throws {
        self.config = config
        quicServer = try QuicServer(config: config)
        callbackQueue = DispatchQueue(label: "com.peer.callbackQueue")
        messageQueue = DispatchQueue(label: "com.peer.messageQueue")
    }

    func start() throws {
        // Implement start logic
        try quicServer?.start()
        quicServer?.onMessageReceived = { [weak self] _ in
            guard let self else { return }
        }
    }

    func close() throws {
        // Implement close logic
    }

    func connectToPeer(
        peerAddr _: NetAddr,
        completion _: @Sendable @escaping (Result<String, Error>) -> Void
    ) {
        // Implement connect logic
    }

    func sendToPeer(
        message: Message, peerAddr: NetAddr,
        completion: @Sendable @escaping (Result<String, Error>) -> Void
    ) {
        // Ensure serial execution using messageQueue
        messageQueue.async { [weak self] in
            guard let self else { return }
            // Simulate sending message using a Task
            Task {
                let isSuccess = await self.simulateSendMessage(message, peerAddr: peerAddr)
                if isSuccess {
                    completion(
                        .success(
                            "Message sent successfully to \(peerAddr.ipAddress):\(peerAddr.port)"
                        )
                    )
                } else {
                    let error = NSError(domain: "SendError", code: 1, userInfo: nil)
                    completion(.failure(error))
                }
            }
        }
    }

    private func simulateSendMessage(_: Message, peerAddr _: NetAddr) async -> Bool {
        // Simulate network delay
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        return true // Simulate successful send
    }

    func callBackMessage(message: Message) throws {
        // Ensure serial execution using messageQueue
        messageQueue.async { [weak self] in
            guard let self else { return }
            // Implement callback logic
            // Simulate callback processing
            Task {
                try await self.simulateCallbackProcessing(message)
            }
        }
    }

    private func simulateCallbackProcessing(_: Message) async throws {
        // Simulate processing delay
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second
    }

    func handleReceivedMessage(_ message: Message) {
        // Ensure serial execution using messageQueue
        messageQueue.async { [weak self] in
            guard let self else { return }
            do {
                // Process the message
                try processMessage(message)
            } catch {
                // Handle exception
                handleException(error)
            }
        }
    }

    private func processMessage(_: Message) throws {
        // Implement message processing logic
        // Throw an error if something goes wrong
    }

    private func handleException(_ error: Error) {
        // Implement exception handling logic
        print("Error processing message: \(error)")

        // Log the error (can be extended to use a logging framework)
        logError(error)

        // Notify caller of the error if necessary
        // This can be done through delegation, notifications, or other mechanisms
    }

    private func logError(_ error: Error) {
        // Implement logging logic, e.g., print to console or write to a file
        print("Logged error: \(error)")
    }

    public func getPeerAddr() -> String {
        "\(config.ipAddress):\(config.port)"
    }

    deinit {
        // Clean up resources if necessary
    }
}
