import Foundation
import NIO
import Testing

@testable import Networking

#if os(macOS)
    import CoreFoundation
    import Security

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
                    ),
                    messageHandler: self
                )
                try peer.start()
                try group.next().scheduleTask(in: .seconds(5)) {
                    Task {
                        do {
                            let quicmessage = try await peer.sendMessageToPeer(
                                message: Message(type: .text, data: Data("Hello, World!".utf8)),
                                peerAddr: NetAddr(ipAddress: "127.0.0.1", port: 4569)
                            )
                            print("Peer message got: \(quicmessage)")
                        } catch {
                            print("Failed to send message: \(error)")
                        }
                    }
                }.futureResult.wait()
//                try group.next().scheduleTask(in: .seconds(10)) {
//                    Task {
//                        do {
//                            let quicmessage = try await peer.sendMessageToPeer(
//                                message: Message(type: .text, data: Data("Hello, swift!".utf8)),
//                                peerAddr: NetAddr(ipAddress: "127.0.0.1", port: 4569)
//                            )
//                            print("Peer message got: \(quicmessage)")
//                        } catch {
//                            print("Failed to send message: \(error)")
//                        }
//                    }
//                }.futureResult.wait()
                try group.next().scheduleTask(in: .minutes(10)) {}.futureResult.wait()

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
                    ), messageHandler: self
                )

                try peer.start()
                try group.next().scheduleTask(in: .seconds(10)) {
                    Task {
                        do {
                            let quicmessage = try await peer.sendMessageToPeer(
                                message: Message(type: .text, data: Data("Hello, World!".utf8)),
                                peerAddr: NetAddr(ipAddress: "127.0.0.1", port: 4568)
                            )
                            print("Message sent: \(quicmessage)")
                        } catch {
                            print("Failed to send message: \(error)")
                        }
                    }
                }.futureResult.wait()

                try group.next().scheduleTask(in: .minutes(10)) {
                    print("scheduleTask end")
                }.futureResult.wait()

            } catch {
                print("Failed to start peer: \(error)")
            }
        }
    }

    extension PeerTests: PeerMessageHandler {
        func didReceivePeerMessage(peer: Peer, messageID: Int64, message: QuicMessage) {
            switch message.type {
            case .received:
                let buffer = message.data!
                print(
                    "Peer \(peer.getPeerAddr()) received: \(String([UInt8](buffer).map { Character(UnicodeScalar($0)) }))"
                )
                let status = peer.replyTo(messageID: messageID, with: buffer)
                print("Peer sent: \(status)")
            case .shutdownComplete:
                break
            default:
                break
            }
        }

        func didReceivePeerError(peer _: Peer, messageID _: Int64, error: QuicError) {
            print("Failed to receive message: \(error)")
        }
    }
#endif
