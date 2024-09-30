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
        @Test func startPeer() async throws {
            do {
                let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
                // Example instantiation of Peer with EventBus
                let eventBus = EventBus()
                let peer = try await Peer(
                    config: QuicConfig(
                        id: "public-key", cert: cert, key: keyFile, alpn: "sample",
                        ipAddress: "127.0.0.1", port: 4568
                    ),
                    eventBus: eventBus
                )
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
                let token1 = await eventBus.subscribe(PeerMessageReceived.self) { event in
                    print(
                        "Received message from peer messageID: \(event.messageID), message: \(event.message)"
                    )
                    let status: QuicStatus = await peer.respondTo(
                        messageID: event.messageID, with: Message(data: event.message.data!)
                    )
                    print("Peer sent: \(status)")
                }

                // Example subscription to PeerErrorReceived
                let token2 = await eventBus.subscribe(PeerErrorReceived.self) { event in
                    print(
                        "Received error from peer messageID: \(event.messageID ?? -1), error: \(event.error)"
                    )
                }
                _ = try await group.next().scheduleTask(in: .seconds(5)) {
                    Task {
                        await eventBus.unsubscribe(token: token1)
                        await eventBus.unsubscribe(token: token2)
                        print("eventBus unsubscribe")
                    }
                }.futureResult.get()
                try await group.next().scheduleTask(in: .seconds(20)) {}.futureResult.get()

            } catch {
                print("Failed to start peer: \(error)")
            }
        }

        @Test func testPeerCommunication() async throws {
            do {
                let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
                let eventBus1 = EventBus()
                let eventBus2 = EventBus()

                // Create two Peer instances
                let peer1 = try await Peer(
                    config: QuicConfig(
                        id: "public-key1", cert: cert, key: keyFile, alpn: "sample",
                        ipAddress: "127.0.0.1", port: 4568
                    ),
                    eventBus: eventBus1
                )

                let peer2 = try await Peer(
                    config: QuicConfig(
                        id: "public-key2", cert: cert, key: keyFile, alpn: "sample",
                        ipAddress: "127.0.0.1", port: 4569
                    ),
                    eventBus: eventBus2
                )

                // Subscribe to PeerMessageReceived for peer1
                let token1 = await eventBus1.subscribe(PeerMessageReceived.self) { event in
                    print(
                        "Peer1 received message from messageID: \(event.messageID), message: \(event.message)"
                    )
                    let status: QuicStatus = await peer1.respondTo(
                        messageID: event.messageID, with: Message(data: event.message.data!)
                    )
                    print("Peer1 sent response: \(status.isFailed ? "Failed" : "Success")")
                }

                // Subscribe to PeerMessageReceived for peer2
                let token2 = await eventBus2.subscribe(PeerMessageReceived.self) { event in
                    print(
                        "Peer2 received message from messageID: \(event.messageID), message: \(event.message)"
                    )
                    let status: QuicStatus = await peer2.respondTo(
                        messageID: event.messageID, with: Message(data: event.message.data!)
                    )
                    print("Peer2 sent response: \(status.isFailed ? "Failed" : "Success")")
                }

                //  Schedule message sending after 5 seconds
                _ = try await group.next().scheduleTask(in: .seconds(2)) {
                    Task {
                        do {
                            for i in 1 ... 5 {
                                let messageToPeer2 = try await peer1.sendMessageToPeer(
                                    message: Message(
                                        data: Data("Hello from Peer1 - Message \(i)".utf8)
                                    ),
                                    peerAddr: NetAddr(ipAddress: "127.0.0.1", port: 4569)
                                )
                                print("Peer1 sent message \(i): \(messageToPeer2)")

                                let messageToPeer1 = try await peer2.sendMessageToPeer(
                                    message: Message(
                                        data: Data("Hello from Peer2 - Message \(i)".utf8)
                                    ),
                                    peerAddr: NetAddr(ipAddress: "127.0.0.1", port: 4568)
                                )
                                print("Peer2 sent message \(i): \(messageToPeer1)")
                            }
                        } catch {
                            print("Failed to send message: \(error)")
                        }
                    }
                }.futureResult.get()

                _ = try await group.next().scheduleTask(in: .seconds(5)) {
                    Task {
                        await eventBus1.unsubscribe(token: token1)
                        await eventBus2.unsubscribe(token: token2)
                        print("eventBus unsubscribe")
                    }
                }.futureResult.get()
                try await group.next().scheduleTask(in: .seconds(5)) {
                    print("scheduleTask end")
                }.futureResult.get()
            } catch {
                print("Failed about peer communication test: \(error)")
            }
        }
    }
#endif
