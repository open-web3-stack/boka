import Foundation
import NIO
import Testing
import Utils

@testable import Networking

#if os(macOS)
    import CoreFoundation
    import Security

    struct Message: PeerMessage {
        public let data: Data
        public init(data: Data) {
            self.data = data
        }

        public func getData() -> Data {
            data
        }
    }

    let cert = Bundle.module.path(forResource: "server", ofType: "cert")!
    let keyFile = Bundle.module.path(forResource: "server", ofType: "key")!

    final class PeerTests {
        @Test func startPeer1() async throws {
            do {
                let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
                // Example instantiation of Peer with EventBus
                let eventBus = EventBus()
                let peer = try Peer(
                    config: QuicConfig(
                        id: "public-key", cert: cert, key: keyFile, alpn: "sample",
                        ipAddress: "127.0.0.1", port: 4568
                    ),
                    eventBus: eventBus
                )
                try peer.start()
                do {
                    let quicmessage = try await peer.sendMessageToPeer(
                        message: Message(data: Data("Hello, World!".utf8)),
                        peerAddr: NetAddr(ipAddress: "127.0.0.1", port: 4569)
                    )
                    print("Peer message got: \(quicmessage)")
                } catch {
                    print("Failed to send: \(error)")
                }

                // Example subscription to PeerMessageReceived
                _ = await eventBus.subscribe(PeerMessageReceived.self) { event in
                    print(
                        "Received message from peer messageID: \(event.messageID), message: \(event.message)"
                    )
                    let status = peer.replyTo(messageID: event.messageID, with: event.message.data!)
                    print("Peer sent: \(status)")
                }

                // Example subscription to PeerErrorReceived
                _ = await eventBus.subscribe(PeerErrorReceived.self) { event in
                    print(
                        "Received error from peer messageID: \(event.messageID ?? -1), error: \(event.error)"
                    )
                }

                try await group.next().scheduleTask(in: .minutes(5)) {}.futureResult.get()

            } catch {
                print("Failed to start peer: \(error)")
            }
        }

        @Test func startPeer2() throws {
            do {
                let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
                let eventBus = EventBus()
                let peer = try Peer(
                    config: QuicConfig(
                        id: "public-key", cert: cert, key: keyFile, alpn: "alpn",
                        ipAddress: "127.0.0.1", port: 4567
                    ), eventBus: eventBus
                )

                try peer.start()
                _ = try group.next().scheduleTask(in: .seconds(10)) {
                    Task {
                        do {
                            let quicmessage = try await peer.sendMessageToPeer(
                                message: Message(data: Data("Hello, World!".utf8)),
                                peerAddr: NetAddr(ipAddress: "127.0.0.1", port: 4568)
                            )
                            print("Message got: \(quicmessage)")
                        } catch {
                            print("Failed to send message: \(error)")
                        }
                    }
                }.futureResult.wait()

                try group.next().scheduleTask(in: .seconds(20)) {
                    print("scheduleTask end")
                }.futureResult.wait()

            } catch {
                print("Failed to start peer: \(error)")
            }
        }
    }
#endif
