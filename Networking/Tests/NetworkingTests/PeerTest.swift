import Foundation
import NIO
import Testing

@testable import Networking

#if os(macOS)
    import CoreFoundation
    import Security
#endif

final class PeerTests {
    @Test func startPeer1() throws {
        do {
            let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
            let peer = try Peer(
                config: PeerConfig(
                    id: "public-key", cert: "cert", key: "key", alpn: "alpn",
                    ipAddress: "127.0.0.1", port: 4568
                )
            )
            try peer.start()
            peer.onDataReceived = { data in
                print(
                    "Peer received: \(String([UInt8](data).map { Character(UnicodeScalar($0)) }))"
                )
            }
            try group.next().scheduleTask(in: .seconds(5)) {
                peer.sendToPeer(
                    message: Message(.text, data: Data("Hello, World!".utf8)),
                    peerAddr: NetAddr(ipAddress: "127.0.0.1", port: 4567),
                    completion: { result in
                        print("Message sent: \(result)")
                    }
                )
            }.futureResult.wait()
            try group.next().scheduleTask(in: .hours(1)) {}.futureResult.wait()

        } catch {
            print("Failed to start peer: \(error)")
        }
    }

    @Test func startPeer2() throws {
        do {
            let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
            let peer = try Peer(
                config: PeerConfig(
                    id: "public-key", cert: "cert", key: "key", alpn: "alpn",
                    ipAddress: "127.0.0.1", port: 4567
                )
            )
            try peer.start()
            peer.onDataReceived = { data in
                print(
                    "Peer received: \(String([UInt8](data).map { Character(UnicodeScalar($0)) }))"
                )
            }
            try group.next().scheduleTask(in: .seconds(10)) {
                peer.sendToPeer(
                    message: Message(.text, data: Data("Hello, World!".utf8)),
                    peerAddr: NetAddr(ipAddress: "127.0.0.1", port: 4567),
                    completion: { result in
                        print("Message sent: \(result)")
                    }
                )
            }.futureResult.wait()
            try group.next().scheduleTask(in: .minutes(10)) {
                print("scheduleTask end")
            }.futureResult.wait()

        } catch {
            print("Failed to start peer: \(error)")
        }
    }
}
