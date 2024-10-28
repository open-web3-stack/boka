import Foundation
import MsQuicSwift
import Testing
import Utils

@testable import Networking

struct PeerTests {
    struct MockMessage: MessageProtocol {
        let data: Data
        func encode() throws -> Data {
            data
        }
    }

    struct MockRequest<Kind: StreamKindProtocol>: RequestProtocol {
        var kind: Kind
        var data: Data
        func encode() throws -> Data {
            let length = UInt32(data.count)
            var lengthData = withUnsafeBytes(of: length.littleEndian) { Data($0) }
            lengthData.append(data)
            return lengthData
        }

        typealias StreamKind = Kind
    }

    public enum UniquePresistentStreamKind: UInt8, StreamKindProtocol {
        case uniqueA = 0x01
        case uniqueB = 0x02
        case uniqueC = 0x03
    }

    public enum EphemeralStreamKind: UInt8, StreamKindProtocol {
        case typeA = 0x04
        case typeB = 0x05
        case typeC = 0x06
    }

    struct MockEphemeralMessageDecoder: MessageDecoder {
        typealias Message = MockRequest<EphemeralStreamKind>

        var data: Data?
        var kind: EphemeralStreamKind

        init(kind: EphemeralStreamKind) {
            self.kind = kind
        }

        mutating func decode(data: Data) throws -> MockRequest<EphemeralStreamKind> {
            self.data = data
            return MockRequest(kind: kind, data: data)
        }

        func finish() -> Data? {
            data
        }
    }

    struct MockUniqueMessageDecoder: MessageDecoder {
        typealias Message = MockRequest<UniquePresistentStreamKind>

        var data: Data?
        var kind: UniquePresistentStreamKind

        init(kind: UniquePresistentStreamKind) {
            self.kind = kind
        }

        mutating func decode(data: Data) throws -> MockRequest<UniquePresistentStreamKind> {
            self.data = data
            return MockRequest(kind: kind, data: data)
        }

        func finish() -> Data? {
            data
        }
    }

    actor DataStorage {
        private(set) var lastReceivedData: Data?

        func updateData(_ data: Data?) {
            lastReceivedData = data
        }
    }

    struct MockEphemeralStreamHandler: EphemeralStreamHandler {
        typealias StreamKind = EphemeralStreamKind
        typealias Request = MockRequest<EphemeralStreamKind>
        private let dataStorage = DataStorage()

        var lastReceivedData: Data? {
            get async { await dataStorage.lastReceivedData }
        }

        func createDecoder(kind: StreamKind) -> any MessageDecoder<Request> {
            MockEphemeralMessageDecoder(kind: kind)
        }

        func handle(connection _: any ConnectionInfoProtocol, request: Request) async throws -> Data {
            let data = request.data
            guard data.count >= 4 else {
                throw NSError(
                    domain: "ExtractError", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Data too short to contain length"]
                )
            }
            let lengthData = data.prefix(4)
            let length = UInt32(
                littleEndian: lengthData.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            )
            let actualData = data.dropFirst(4).prefix(Int(length))
            await dataStorage.updateData(actualData)
            return actualData
        }
    }

    struct MockPresentStreamHandler: PresistentStreamHandler {
        private let dataStorage = DataStorage()

        var lastReceivedData: Data? {
            get async { await dataStorage.lastReceivedData }
        }

        func streamOpened(
            connection _: any Networking.ConnectionInfoProtocol,
            stream _: any Networking.StreamProtocol<PeerTests.MockRequest<PeerTests.UniquePresistentStreamKind>>,
            kind _: PeerTests.UniquePresistentStreamKind
        ) async throws {}

        func handle(
            connection _: any Networking.ConnectionInfoProtocol,
            message: PeerTests.MockRequest<PeerTests.UniquePresistentStreamKind>
        ) async throws {
            let data = message.data
            await dataStorage.updateData(data)
        }

        typealias StreamKind = UniquePresistentStreamKind
        typealias Request = MockRequest<UniquePresistentStreamKind>

        func createDecoder(kind: StreamKind) -> any MessageDecoder<Request> {
            MockUniqueMessageDecoder(kind: kind)
        }
    }

    struct MockStreamHandler: StreamHandler {
        typealias PresistentHandler = MockPresentStreamHandler

        typealias EphemeralHandler = MockEphemeralStreamHandler
    }

    @Test
    func peerBroadcast() async throws {
        let handler1 = MockPresentStreamHandler()
        let handler2 = MockPresentStreamHandler()

        let peer1 = try Peer(
            options: PeerOptions<MockStreamHandler>(
                role: .validator,
                listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 8081)!,
                genesisHeader: Data32(),
                secretKey: Ed25519.SecretKey(from: Data32()),
                presistentStreamHandler: handler1,
                ephemeralStreamHandler: MockEphemeralStreamHandler(),
                serverSettings: .defaultSettings,
                clientSettings: .defaultSettings
            )
        )
        let peer2 = try Peer(
            options: PeerOptions<MockStreamHandler>(
                role: .validator,
                listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 8082)!,
                genesisHeader: Data32(),
                secretKey: Ed25519.SecretKey(from: Data32()),
                presistentStreamHandler: handler2,
                ephemeralStreamHandler: MockEphemeralStreamHandler(),
                serverSettings: .defaultSettings,
                clientSettings: .defaultSettings
            )
        )
        try? await Task.sleep(for: .milliseconds(100))
        _ = try peer1.connect(
            to: NetAddr(ipAddress: "127.0.0.1", port: 8082)!, role: .validator
        )
        _ = try peer2.connect(
            to: NetAddr(ipAddress: "127.0.0.1", port: 8081)!, role: .validator
        )
        try? await Task.sleep(for: .milliseconds(100))
        peer1.broadcast(
            kind: .uniqueA, message: .init(kind: .uniqueA, data: Data("hello world".utf8))
        )
        try? await Task.sleep(for: .milliseconds(100))
        peer2.broadcast(
            kind: .uniqueB, message: .init(kind: .uniqueB, data: Data("I am jam".utf8))
        )
        // Verify last received data
        try? await Task.sleep(for: .milliseconds(1000))
        await #expect(handler2.lastReceivedData == Data("hello world".utf8))
        await #expect(handler1.lastReceivedData == Data("I am jam".utf8))
    }

    @Test
    func peerRequest() async throws {
        let peer1 = try Peer(
            options: PeerOptions<MockStreamHandler>(
                role: .validator,
                listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 8083)!,
                genesisHeader: Data32(),
                secretKey: Ed25519.SecretKey(from: Data32()),
                presistentStreamHandler: MockPresentStreamHandler(),
                ephemeralStreamHandler: MockEphemeralStreamHandler(),
                serverSettings: .defaultSettings,
                clientSettings: .defaultSettings
            )
        )
        let peer2 = try Peer(
            options: PeerOptions<MockStreamHandler>(
                role: .validator,
                listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 8084)!,
                genesisHeader: Data32(),
                secretKey: Ed25519.SecretKey(from: Data32()),
                presistentStreamHandler: MockPresentStreamHandler(),
                ephemeralStreamHandler: MockEphemeralStreamHandler(),
                serverSettings: .defaultSettings,
                clientSettings: .defaultSettings
            )
        )
        try? await Task.sleep(for: .milliseconds(100))

        let connection1 = try peer1.connect(
            to: NetAddr(ipAddress: "127.0.0.1", port: 8084)!, role: .validator
        )
        try? await Task.sleep(for: .milliseconds(100))

        let dataList1 = try await connection1.request(
            MockRequest(kind: .typeA, data: Data("hello world".utf8))
        )
        #expect(dataList1 == Data("hello world".utf8))

        let connection2 = try peer2.connect(
            to: NetAddr(ipAddress: "127.0.0.1", port: 8083)!, role: .validator
        )
        try? await Task.sleep(for: .milliseconds(100))

        let dataList2 = try await connection2.request(
            MockRequest(kind: .typeB, data: Data("I am jam".utf8))
        )
        #expect(dataList2 == Data("I am jam".utf8))
    }

    @Test
    func multiplePeerBroadcast() async throws {
        var peers: [Peer<MockStreamHandler>] = []
        // Create 100 peer nodes
        for i in 0 ..< 100 {
            let peer = try Peer(
                options: PeerOptions<MockStreamHandler>(
                    role: .builder,
                    listenAddress: NetAddr(ipAddress: "127.0.0.1", port: UInt16(7081 + i))!,
                    genesisHeader: Data32(),
                    secretKey: Ed25519.SecretKey(from: Data32()),
                    presistentStreamHandler: MockPresentStreamHandler(),
                    ephemeralStreamHandler: MockEphemeralStreamHandler(),
                    serverSettings: .defaultSettings,
                    clientSettings: .defaultSettings
                )
            )
            peers.append(peer)
        }

        try? await Task.sleep(for: .milliseconds(100))

        // Connect each peer to the next one in a circular network
        for i in 0 ..< peers.count {
            let nextPeerIndex = (i + 1) % peers.count
            _ = try peers[i].connect(
                to: NetAddr(ipAddress: "127.0.0.1", port: UInt16(7081 + nextPeerIndex))!,
                role: .validator
            )
        }

        try? await Task.sleep(for: .milliseconds(100))

        // Broadcast a message from each peer
        for (i, peer) in peers.enumerated() {
            let message = MockRequest(
                kind: i % 2 == 0 ? UniquePresistentStreamKind.uniqueA : UniquePresistentStreamKind.uniqueB,
                data: Data("Message from peer \(i)".utf8)
            )
            peer.broadcast(kind: message.kind, message: message)
        }

        // Wait for message propagation
        try? await Task.sleep(for: .milliseconds(200))
    }

    @Test
    func multiplePeerRequest() async throws {
        var peers: [Peer<MockStreamHandler>] = []

        // Create 100 peer nodes
        for i in 0 ..< 100 {
            let peer = try Peer(
                options: PeerOptions<MockStreamHandler>(
                    role: .builder,
                    listenAddress: NetAddr(ipAddress: "127.0.0.1", port: UInt16(6091 + i))!,
                    genesisHeader: Data32(),
                    secretKey: Ed25519.SecretKey(from: Data32()),
                    presistentStreamHandler: MockPresentStreamHandler(),
                    ephemeralStreamHandler: MockEphemeralStreamHandler(),
                    serverSettings: .defaultSettings,
                    clientSettings: .defaultSettings
                )
            )
            peers.append(peer)
        }

        // Wait for peers to initialize
        try? await Task.sleep(for: .milliseconds(100))

        // Test request-response by having each peer request from the next peer
        for i in 0 ..< 100 {
            let messageData = Data("Request from peer \(i)".utf8)
            let port = UInt16(6091 + (i + 1) % 100)
            let type = (i + 1) % 2 == 0 ? EphemeralStreamKind.typeA : EphemeralStreamKind.typeB
            let response = try await peers[i].connect(
                to: NetAddr(ipAddress: "127.0.0.1", port: port)!,
                role: .validator
            ).request(MockRequest(kind: type, data: messageData))
            #expect(response == messageData, "Peer \(i) should receive correct response")
        }
    }

    @Test
    func highConcurrentRequest() async throws {
        var peers: [Peer<MockStreamHandler>] = []

        // Create 100 peers
        for i in 0 ..< 100 {
            let peer = try Peer(
                options: PeerOptions<MockStreamHandler>(
                    role: .validator,
                    listenAddress: NetAddr(ipAddress: "127.0.0.1", port: UInt16(8300 + i))!,
                    genesisHeader: Data32(),
                    secretKey: Ed25519.SecretKey(from: Data32()),
                    presistentStreamHandler: MockPresentStreamHandler(),
                    ephemeralStreamHandler: MockEphemeralStreamHandler(),
                    serverSettings: .defaultSettings,
                    clientSettings: .defaultSettings
                )
            )
            peers.append(peer)
        }

        for i in 0 ..< peers.count - 1 {
            _ = try peers[i].connect(
                to: NetAddr(ipAddress: "127.0.0.1", port: UInt16(8300 + i + 1))!,
                role: .validator
            )
        }

        // Allow connections to establish
        try? await Task.sleep(for: .milliseconds(100))

        // Send multiple requests from each peer
        for peer in peers {
            let tasks = (1 ... 88).map { _ in
                Task {
                    let net = try peer.listenAddress()
                    let random = Int(arc4random_uniform(100))
                    let type = random % 2 == 0 ? EphemeralStreamKind.typeA : EphemeralStreamKind.typeB
                    let messageData = Data("Concurrent request \(net.description) + \(random)".utf8)
                    let response = try await peer.connect(
                        to: net,
                        role: .validator
                    ).request(MockRequest(kind: type, data: messageData))
                    #expect(response == messageData, "Peer should receive correct response")
                }
            }
            // Wait for all tasks to complete
            for task in tasks {
                try await task.value
            }
        }
    }

    @Test
    func broadcastSynchronization() async throws {
        var peers: [Peer<MockStreamHandler>] = []
        var handles: [MockPresentStreamHandler] = []

        // Create 50 peers with unique addresses
        for i in 0 ..< 50 {
            let handle = MockPresentStreamHandler()
            let peer = try Peer(
                options: PeerOptions<MockStreamHandler>(
                    role: .validator,
                    listenAddress: NetAddr(ipAddress: "127.0.0.1", port: UInt16(100 + i))!,
                    genesisHeader: Data32(),
                    secretKey: Ed25519.SecretKey(from: Data32()),
                    presistentStreamHandler: handle,
                    ephemeralStreamHandler: MockEphemeralStreamHandler(),
                    serverSettings: .defaultSettings,
                    clientSettings: .defaultSettings
                )
            )
            handles.append(handle)
            peers.append(peer)
        }

        // Connect each peer to form a fully connected network
        for i in 0 ..< peers.count {
            for j in 0 ..< peers.count where i != j {
                _ = try peers[i].connect(
                    to: NetAddr(ipAddress: "127.0.0.1", port: UInt16(100 + j))!,
                    role: .validator
                )
            }
        }

        // Wait for all connections to establish
        try? await Task.sleep(for: .seconds(10))

        let centralPeer = peers[0]
        let messagedata = Data("Sync message".utf8)
        centralPeer.broadcast(kind: .uniqueA, message: MockRequest(kind: .uniqueA, data: messagedata))

        // Wait for message to propagate
        try? await Task.sleep(for: .seconds(60))

        // Check that each peer received the broadcast
        for i in 1 ..< handles.count {
            let receivedData = await handles[i].lastReceivedData
            #expect(receivedData == messagedata, "Handle should have received the broadcast message")
        }
    }
}
