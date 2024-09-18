import Foundation
import NIO
import Testing

@testable import Networking

#if os(macOS)
    import CoreFoundation
    import Security

    final class QuicServerTests {
        @Test func start() throws {
            do {
                let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
                let quicServer = try QuicServer(
                    config: QuicConfig(
                        id: "public-key", cert: cert, key: keyFile, alpn: "sample",
                        ipAddress: "127.0.0.1", port: 4568
                    ), messageHandler: self
                )
                try quicServer.start()

                try group.next().scheduleTask(in: .hours(1)) {}.futureResult.wait()
            } catch {
                print("Failed to start quic server: \(error)")
            }
        }
    }

    extension QuicServerTests: QuicServerMessageHandler {
        func didReceiveMessage(quicServer: QuicServer, messageID: Int64, message: QuicMessage) {
            switch message.type {
            case .received:
                print("Server received message with ID \(messageID): \(message)")
                quicServer.replyTo(messageID: messageID, with: message.data!)
            case .shutdownComplete:
                print("Server shutdown complete")
            case .aborted:
                print("Server aborted")
            case .unknown:
                print("Server unknown")
            default:
                break
            }
        }

        func didReceiveError(quicServer _: QuicServer, messageID _: Int64, error: QuicError) {
            print("Server error: \(error)")
        }
    }
#endif
