import Foundation
import NIO
import Testing

@testable import Networking

#if os(macOS)
    import CoreFoundation
    import Security
#endif

struct Message: PeerMessage {
    public let timestamp: Int
    public let type: MessageType
    public let data: Data

    public init(type: MessageType, data: Data) {
        timestamp = Int(Date().timeIntervalSince1970 * 1000)
        self.type = type
        self.data = data
    }
}

let cert = "/Users/mackun/boka/Networking/Sources/assets/server.cert"
let keyFile = "/Users/mackun/boka/Networking/Sources/assets/server.key"

final class PeerTests {
    @Test func startPeer1() throws {
        do {
            let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
            let peer = try Peer(
                config: QuicConfig(
                    id: "public-key", cert: cert, key: keyFile, alpn: "sample",
                    ipAddress: "127.0.0.1", port: 4568
                )
            )
            try peer.start()
            try group.next().scheduleTask(in: .hours(1)) {}.futureResult.wait()

        } catch {
            print("Failed to start peer: \(error)")
        }
    }

    @Test func startPeer2() throws {
        do {
            let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
            let peer = try Peer(
                config: QuicConfig(
                    id: "public-key", cert: cert, key: keyFile, alpn: "alpn",
                    ipAddress: "127.0.0.1", port: 4567
                )
            )

            try peer.start()
            try group.next().scheduleTask(in: .seconds(10)) {}.futureResult.wait()
            try group.next().scheduleTask(in: .minutes(10)) {
                print("scheduleTask end")
            }.futureResult.wait()

        } catch {
            print("Failed to start peer: \(error)")
        }
    }
}
