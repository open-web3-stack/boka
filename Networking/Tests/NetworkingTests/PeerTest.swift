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
        public let type: PeerMessageType?
        public init(data: Data) {
            self.data = data
            type = nil
        }

        public init(data: Data, type: PeerMessageType) {
            self.data = data
            self.type = type
        }

        public func getMessageType() -> PeerMessageType {
            type ?? .uniquePersistent
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
                    let message: QuicMessage = try await peer.sendMessage(
                        to: NetAddr(ipAddress: "127.0.0.1", port: 4569),
                        with: Message(data: Data("Hello, World!".utf8))
                    )
                    print("Peer message got: \(message)")
                } catch {
                    print("Failed to send: \(error)")
                }

                // Example subscription to PeerMessageReceived
                let token1 = await eventBus.subscribe(PeerMessageReceived.self) { event in
                    print(
                        "Received message from peer messageID: \(event.messageID), message: message: \(String([UInt8](event.message.data!).map { Character(UnicodeScalar($0)) }))"
                    )
                    let status: QuicStatus = await peer.respond(
                        to: event.messageID, with: Message(data: event.message.data!)
                    )
                    print("Peer sent status: \(status.isFailed ? "Failed" : "Successed")")
                }

                // Example subscription to PeerErrorReceived
                let token2 = await eventBus.subscribe(PeerErrorReceived.self) { event in
                    print(
                        "Received error from peer messageID: \(event.messageID ?? -1), error: \(event.error)"
                    )
                }

                _ = try await group.next().scheduleTask(in: .seconds(10)) {
                    Task {
                        await eventBus.unsubscribe(token: token1)
                        await eventBus.unsubscribe(token: token2)
                        print("eventBus unsubscribe")
                    }
                }.futureResult.get()

                try await group.next().scheduleTask(in: .seconds(5)) {
                    print("task end")
                }.futureResult.get()

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
                        "Peer1 received message from messageID: \(event.messageID), message: \(String([UInt8](event.message.data!).map { Character(UnicodeScalar($0)) }))"
                    )
                    let status: QuicStatus = await peer1.respond(to: event.messageID, with: event.message.data!)
                    print("Peer1 sent response: \(status.isFailed ? "Failed" : "Success")")
                }

                // Subscribe to PeerMessageReceived for peer2
                let token2 = await eventBus2.subscribe(PeerMessageReceived.self) { event in
                    print(
                        "Peer2 received message from messageID: \(event.messageID), message: \(String([UInt8](event.message.data!).map { Character(UnicodeScalar($0)) }))"
                    )
                    let status: QuicStatus = await peer2.respond(to: event.messageID, with: event.message.data!)
                    print("Peer2 sent response: \(status.isFailed ? "Failed" : "Success")")
                }

                //  Schedule message sending after 5 seconds
                _ = try await group.next().scheduleTask(in: .seconds(2)) {
                    Task {
                        do {
                            for i in 1 ... 5 {
                                let messageToPeer2: QuicMessage = try await peer1.sendMessage(
                                    to: NetAddr(ipAddress: "127.0.0.1", port: 4569),
                                    with: Message(
                                        data: Data("Hello from Peer1 - Message \(i)".utf8),
                                        type: PeerMessageType.commonEphemeral
                                    )
                                )
                                print("Peer1 got message: \(String([UInt8](messageToPeer2.data!).map { Character(UnicodeScalar($0)) }))")
                                let messageToPeer1: QuicMessage = try await peer2.sendMessage(
                                    to: NetAddr(ipAddress: "127.0.0.1", port: 4568),
                                    with: Message(
                                        data: Data("Hello from Peer2 - Message \(i)".utf8),
                                        type: PeerMessageType.commonEphemeral
                                    )
                                )
                                print("Peer2 got message: \(String([UInt8](messageToPeer1.data!).map { Character(UnicodeScalar($0)) }))")
                            }

                            for i in 6 ... 10 {
                                let messageToPeer2: QuicMessage = try await peer1.sendMessage(
                                    to: NetAddr(ipAddress: "127.0.0.1", port: 4569),
                                    with: Message(
                                        data: Data("Hello from Peer1 - Message \(i)".utf8),
                                        type: PeerMessageType.uniquePersistent
                                    )
                                )
                                print("Peer1 sent message \(i): \(messageToPeer2)")
                                let messageToPeer1: QuicMessage = try await peer2.sendMessage(
                                    to: NetAddr(ipAddress: "127.0.0.1", port: 4568),
                                    with: Message(
                                        data: Data("Hello from Peer2 - Message \(i)".utf8),
                                        type: PeerMessageType.uniquePersistent
                                    )
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
