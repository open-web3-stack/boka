// import Foundation
// import NIO
// import Testing
//
// @testable import Networking
//
// #if os(macOS)
//    import CoreFoundation
//    import Security
//
//    final class QuicServerTests {
//        @Test func start() async throws {
//            do {
//                let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
//                let quicServer = try await QuicServer(
//                    config: QuicConfig(
//                        id: "public-key", cert: cert, key: keyFile, alpn: "sample",
//                        ipAddress: "127.0.0.1", port: 4568
//                    ), messageHandler: self
//                )
//                quicServer.closeSync()
//
//
//                try await group.next().scheduleTask(in: .seconds(5)) {}.futureResult.get()
//            } catch {
//                print("Failed to start quic server: \(error)")
//            }
//        }
//    }
//
//    extension QuicServerTests: QuicServerMessageHandler {
//        func didReceiveMessage(quicServer: QuicServer, messageID: Int64, message: QuicMessage) {
//            switch message.type {
//            case .received:
//                print("Server received message with ID \(messageID): \(message)")
//                Task {
//                    _ = await quicServer.respondTo(messageID: messageID, with: message.data!,kind: .commonEphemeral)
//
//                }
//            case .shutdownComplete:
//                print("Server shutdown complete")
//            case .unknown:
//                print("Server unknown")
//            default:
//                break
//            }
//        }
//
//        func didReceiveError(quicServer _: QuicServer, messageID _: Int64, error: QuicError) {
//            print("Server error: \(error)")
//        }
//    }
// #endif
