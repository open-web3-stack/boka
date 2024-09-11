import Foundation
import NIO
import Testing

@testable import Networking

#if os(macOS)
    import CoreFoundation
    import Security
#endif

final class QuicClientTests {
    @Test func start() throws {
        do {
            let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
            let quicClient = try QuicClient(
                config: QuicConfig(
                    id: "public-key", cert: cert, key: keyFile, alpn: "sample",
                    ipAddress: "127.0.0.1", port: 4568
                )
            )
            let status = try quicClient.start()
            print(status)
            quicClient.onMessageReceived = { result in
                switch result {
                case let .success(message):
                    print("Client received: \(message)")
                case let .failure(error):
                    print("Client error: \(error)")
                }
            }
            try group.next().scheduleTask(in: .seconds(5)) {
                try quicClient.send(message: Data("Hello, World!".utf8))
            }.futureResult.wait()
            try group.next().scheduleTask(in: .hours(1)) {}.futureResult.wait()
        } catch {
            print("Failed to start quic client: \(error)")
        }
    }
}
