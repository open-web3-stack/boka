import Foundation
import NIO
import Testing

@testable import Networking

#if os(macOS)
    import CoreFoundation
    import Security
#endif

final class QuicServerTests {
    @Test func start() throws {
        do {
            let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
            let quicServer = try QuicServer(
                config: QuicConfig(
                    id: "public-key", cert: cert, key: keyFile, alpn: "sample",
                    ipAddress: "127.0.0.1", port: 4568
                )
            )

            quicServer.onMessageReceived = { result, completion in
                switch result {
                case let .success(message):
                    print("Server received: \(message)")
                    switch message.type {
                    case .received:
                        let buffer = message.data!
                        print(
                            "Server received: \(String([UInt8](buffer).map { Character(UnicodeScalar($0)) }))"
                        )
                        completion(buffer)
                    default:
                        break
                    }
                case let .failure(error):
                    print("Server error: \(error)")
                }
            }
            try quicServer.start()
            try group.next().scheduleTask(in: .hours(1)) {}.futureResult.wait()
        } catch {
            print("Failed to start quic server: \(error)")
        }
    }
}
