import Foundation
import NIO
import Testing

@testable import Networking

#if os(macOS)
    import CoreFoundation
    import Security

    final class QuicClientTests {
        @Test func start() async throws {
            let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
            let cert = Bundle.module.path(forResource: "server", ofType: "cert")!
            let keyFile = Bundle.module.path(forResource: "server", ofType: "key")!
            let quicClient = try QuicClient(
                config: QuicConfig(
                    id: "public-key", cert: cert, key: keyFile, alpn: "sample",
                    ipAddress: "127.0.0.1", port: 4569
                )
            )
            do {
                let message1 = try await quicClient.send(
                    message: Data("Hello, World!".utf8), streamKind: .uniquePersistent
                )
                print("Client received 1: \(message1)")
                let message2 = try await quicClient.send(
                    message: Data("Hello, swift!".utf8), streamKind: .commonEphemeral
                )
                print("Client received 2: \(message2)")
                let message3 = try await quicClient.send(
                    message: Data("Hello, how are you!".utf8), streamKind: .uniquePersistent
                )
                print("Client received 3: \(message3)")
                let message4 = try await quicClient.send(
                    message: Data("Hello, i am fine!".utf8), streamKind: .commonEphemeral
                )
                print("Client received 4: \(message4)")

            } catch {
                // Handle the error if sending the message fails or if the connection fails
                print("Failed about quic client: \(error)")
            }

            try await group.next().scheduleTask(in: .seconds(5)) {
                print("scheduleTask: 5s")
            }.futureResult.get()
        }
    }
#endif
