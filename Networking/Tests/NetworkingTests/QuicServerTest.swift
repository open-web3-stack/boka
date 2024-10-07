import Foundation
import NIO
import Testing

@testable import Networking

#if os(macOS)
    import CoreFoundation
    import Security
#endif
final class QuicServerTests {
    @Test func start() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        let quicServer = try await QuicServer(
            config: QuicConfig(
                id: "public-key", cert: cert, key: keyFile, alpn: "sample",
                ipAddress: "127.0.0.1", port: 4561
            ), messageHandler: self
        )
        try await group.next().scheduleTask(in: .seconds(5)) {}.futureResult.get()
    }
}

extension QuicServerTests: QuicServerMessageHandler {
    func didReceiveMessage(server: QuicServer, messageID: Int64, message: QuicMessage) async {
        switch message.type {
        case .received:
            let messageString = String(
                [UInt8](message.data!).map { Character(UnicodeScalar($0)) }
            )
            print("Server received message : \(messageString)")
            _ = await server.respondGetStatus(to: messageID, with: message.data!)
        case .shutdownComplete:
            print("Server shutdown complete")
        case .unknown:
            print("Server unknown")
        default:
            break
        }
    }

    func didReceiveError(server _: QuicServer, messageID _: Int64, error: QuicError) async {
        print("Server error: \(error)")
    }
}
