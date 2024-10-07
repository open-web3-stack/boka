import Foundation
import NIO
import Testing

@testable import Networking

#if os(macOS)
    import CoreFoundation
    import Security
#endif
final class QuicClientTests {
    @Test func start() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        let cert = Bundle.module.path(forResource: "server", ofType: "cert")!
        let keyFile = Bundle.module.path(forResource: "server", ofType: "key")!
        let quicServer = try await QuicServer(
            config: QuicConfig(
                id: "public-key", cert: cert, key: keyFile, alpn: "sample",
                ipAddress: "127.0.0.1", port: 4565
            ), messageHandler: self
        )
        try await group.next().scheduleTask(in: .seconds(5)) {}.futureResult.get()
        let quicClient = try await QuicClient(
            config: QuicConfig(
                id: "public-key", cert: cert, key: keyFile, alpn: "sample",
                ipAddress: "127.0.0.1", port: 4565
            )
        )

        for i in 1 ... 10 {
            let messageToPeer2: QuicStatus = try await quicClient.send(
                data: Data("Hello from Client - Message \(i)".utf8),
                streamKind: .commonEphemeral
            )
            print("Client sent message \(i): \(messageToPeer2.isSucceeded ? "Success" : "Failed")")
            let messageToPeer1: QuicStatus = try await quicClient.send(
                data: Data("Hello from Client - Message \(i + 10)".utf8),
                streamKind: .commonEphemeral
            )
            print("Client sent message \(i + 10): \(messageToPeer1.isSucceeded ? "Success" : "Failed")")
        }

        try await group.next().scheduleTask(in: .seconds(125)) {
            print("scheduleTask: 5s")
        }.futureResult.get()
    }
}

extension QuicClientTests: QuicServerMessageHandler {
    func didReceiveMessage(server: QuicServer, messageID: Int64, message: QuicMessage) async {
        switch message.type {
        case .received:
            let messageString = String(
                [UInt8](message.data!).map { Character(UnicodeScalar($0)) }
            )
            print("Server received message : \(messageString)")
            let status = await server.respondGetStatus(to: messageID, with: message.data!)
            print("Server response message : \(status.isSucceeded ? "Success" : "Failed")")
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
