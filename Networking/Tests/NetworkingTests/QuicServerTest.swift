import Foundation
import NIO
import Testing

@testable import Networking

#if os(macOS)
    import CoreFoundation
    import Security
#endif

final class QuicServerTests: QuicServerDelegate {
    func didReceiveMessage(
        quicServer: QuicServer, messageID: Int64, result: Result<QuicMessage, QuicError>
    ) {
        switch result {
        case let .success(message):
            print("Server received message with ID \(messageID): \(message)")
            quicServer.sendMessage(message.data!, to: messageID)
        case let .failure(error):
            print("Server error: \(error)")
        }
    }

    @Test func start() throws {
        do {
            let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
            let quicServer = try QuicServer(
                config: QuicConfig(
                    id: "public-key", cert: cert, key: keyFile, alpn: "sample",
                    ipAddress: "127.0.0.1", port: 4568
                )
            )
            quicServer.delegate = self
            try quicServer.start()

            try group.next().scheduleTask(in: .hours(1)) {}.futureResult.wait()
        } catch {
            print("Failed to start quic server: \(error)")
        }
    }
}
