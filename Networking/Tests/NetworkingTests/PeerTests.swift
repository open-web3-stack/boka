import Foundation
import MsQuicSwift
import Testing
import TracingUtils
import Utils

@testable import Networking

struct PeerTests {
    struct MockRequest<Kind: StreamKindProtocol>: RequestProtocol {
        var kind: Kind
        var data: [Data]
        func encode() throws -> [Data] {
            data
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

    struct MockEphemeralMessageDecoder: EphemeralStreamMessageDecoder {
        typealias Message = MockRequest<EphemeralStreamKind>

        var data: [Data]?
        var kind: EphemeralStreamKind

        init(kind: EphemeralStreamKind) {
            self.kind = kind
        }

        mutating func decode(data: [Data]) throws -> MockRequest<EphemeralStreamKind> {
            self.data = data
            return MockRequest(kind: kind, data: data)
        }
    }

    struct MockUniqueMessageDecoder: PresistentStreamMessageDecoder {
        typealias Message = MockRequest<UniquePresistentStreamKind>

        var data: Data?
        var kind: UniquePresistentStreamKind

        init(kind: UniquePresistentStreamKind) {
            self.kind = kind
        }

        mutating func decode(data: Data) throws -> MockRequest<UniquePresistentStreamKind> {
            self.data = data
            return MockRequest(kind: kind, data: [data])
        }
    }

    actor DataStorage {
        private(set) var data: [[Data]] = []

        func updateData(_ data: [Data]) {
            self.data.append(data)
        }
    }

    struct MockEphemeralStreamHandler: EphemeralStreamHandler {
        typealias StreamKind = EphemeralStreamKind
        typealias Request = MockRequest<EphemeralStreamKind>
        private let dataStorage: PeerTests.DataStorage = DataStorage()

        func createDecoder(kind: StreamKind) -> any EphemeralStreamMessageDecoder<Request> {
            MockEphemeralMessageDecoder(kind: kind)
        }

        func handle(connection _: any ConnectionInfoProtocol, request: Request) async throws -> [Data] {
            var data = request.data
            data[data.endIndex - 1] += Data(" response".utf8)
            await dataStorage.updateData(data)
            return data
        }
    }

    final class MockPresistentStreamHandler: PresistentStreamHandler {
        private let dataStorage = DataStorage()

        var lastReceivedData: [Data]? {
            get async { await dataStorage.data.last }
        }

        var receivedData: [[Data]] {
            get async { await dataStorage.data }
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

        func createDecoder(kind: StreamKind) -> any PresistentStreamMessageDecoder<Request> {
            MockUniqueMessageDecoder(kind: kind)
        }
    }

    struct MockStreamHandler: StreamHandler {
        typealias PresistentHandler = MockPresistentStreamHandler

        typealias EphemeralHandler = MockEphemeralStreamHandler
    }

    @Test
    func connectionRotationStrategy() async throws {
        var peers: [Peer<MockStreamHandler>] = []
        var handlers: [MockPresistentStreamHandler] = []
        let centerPeer = try Peer(
            options: PeerOptions<MockStreamHandler>(
                role: .validator,
                listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 0)!,
                genesisHeader: Data32(),
                secretKey: Ed25519.SecretKey(from: Data32(repeating: 255)),
                persistentStreamHandler: MockPresistentStreamHandler(),
                ephemeralStreamHandler: MockEphemeralStreamHandler(),
                serverSettings: .defaultSettings,
                clientSettings: .defaultSettings,
                peerSettings: PeerSettings(maxBuilderConnections: 3)
            )
        )
        // Create 5 peer nodes
        for i in 0 ..< 5 {
            let handler = MockPresistentStreamHandler()
            handlers.append(handler)
            let peer = try Peer(
                options: PeerOptions<MockStreamHandler>(
                    role: .builder,
                    listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 0)!,
                    genesisHeader: Data32(),
                    secretKey: Ed25519.SecretKey(from: Data32(repeating: UInt8(i))),
                    persistentStreamHandler: handler,
                    ephemeralStreamHandler: MockEphemeralStreamHandler(),
                    serverSettings: .defaultSettings,
                    clientSettings: .defaultSettings
                )
            )
            peers.append(peer)
        }

        // Make some connections
        for i in 0 ..< 5 {
            let peer = peers[i]
            let con = try peer.connect(to: centerPeer.listenAddress(), role: .builder)
            try await con.ready()
        }

        #expect(centerPeer.peersCount == 3)

        centerPeer.broadcast(kind: .uniqueA, message: .init(kind: .uniqueA, data: [Data("connection rotation strategy".utf8)]))
        try? await Task.sleep(for: .milliseconds(100))
        var receivedCount = 0
        for handler in handlers {
            receivedCount += await handler.receivedData.count
        }
        #expect(receivedCount == 3)
    }

    @Test
    func mockHandshakeFailure() async throws {
        let mockPeerTest = try MockPeerEventTests()
        let serverHandler = MockPeerEventTests.MockPeerEventHandler(
            MockPeerEventTests.MockPeerEventHandler.MockPeerAction.mockHandshakeFailure
        )
        let alpns = [
            PeerRole.validator: Alpn(genesisHeader: Data32(), builder: false).data,
            PeerRole.builder: Alpn(genesisHeader: Data32(), builder: true).data,
        ]
        let allAlpns = Array(alpns.values)
        // Server setup with bad certificate
        let serverConfiguration = try QuicConfiguration(
            registration: mockPeerTest.registration,
            pkcs12: mockPeerTest.certData,
            alpns: allAlpns,
            client: false,
            settings: QuicSettings.defaultSettings
        )

        let listener = try QuicListener(
            handler: serverHandler,
            registration: mockPeerTest.registration,
            configuration: serverConfiguration,
            listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 0)!,
            alpns: allAlpns
        )

        let listenAddress = try listener.listenAddress()
        let peer1 = try Peer(
            options: PeerOptions<MockStreamHandler>(
                role: .validator,
                listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 0)!,
                genesisHeader: Data32(),
                secretKey: Ed25519.SecretKey(from: Data32(repeating: 1)),
                persistentStreamHandler: MockPresistentStreamHandler(),
                ephemeralStreamHandler: MockEphemeralStreamHandler(),
                serverSettings: .defaultSettings,
                clientSettings: .defaultSettings
            )
        )

        let connection1 = try peer1.connect(to: listenAddress, role: .validator)
        try? await Task.sleep(for: .milliseconds(3000))
        #expect(throws: Error.self) {
            _ = try connection1.createStream(kind: .typeA)
        }
        #expect(throws: Error.self) {
            _ = try connection1.createStream(kind: .uniqueA)
        }
        #expect(connection1.isClosed == true)
    }

    @Test
    func mockShutdownBadCert() async throws {
        let mockPeerTest = try MockPeerEventTests()
        let serverHandler = MockPeerEventTests.MockPeerEventHandler()
        let alpns = [
            PeerRole.validator: Alpn(genesisHeader: Data32(), builder: false).data,
            PeerRole.builder: Alpn(genesisHeader: Data32(), builder: true).data,
        ]
        let allAlpns = Array(alpns.values)
        // Server setup with bad certificate
        let serverConfiguration = try QuicConfiguration(
            registration: mockPeerTest.registration,
            pkcs12: mockPeerTest.badCertData,
            alpns: allAlpns,
            client: false,
            settings: QuicSettings.defaultSettings
        )

        let listener = try QuicListener(
            handler: serverHandler,
            registration: mockPeerTest.registration,
            configuration: serverConfiguration,
            listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 0)!,
            alpns: allAlpns
        )

        let listenAddress = try listener.listenAddress()
        let peer1 = try Peer(
            options: PeerOptions<MockStreamHandler>(
                role: .validator,
                listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 0)!,
                genesisHeader: Data32(),
                secretKey: Ed25519.SecretKey(from: Data32(repeating: 1)),
                persistentStreamHandler: MockPresistentStreamHandler(),
                ephemeralStreamHandler: MockEphemeralStreamHandler(),
                serverSettings: .defaultSettings,
                clientSettings: .defaultSettings
            )
        )

        let connection1 = try peer1.connect(to: listenAddress, role: .validator)
        try? await Task.sleep(for: .milliseconds(1000))
        #expect(connection1.isClosed == true)
    }

    @Test
    func reopenUpStream() async throws {
        let handler2 = MockPresistentStreamHandler()
        var messageData = [Data("reopen up stream".utf8)]
        let peer1 = try Peer(
            options: PeerOptions<MockStreamHandler>(
                role: .validator,
                listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 0)!,
                genesisHeader: Data32(),
                secretKey: Ed25519.SecretKey(from: Data32(repeating: 1)),
                persistentStreamHandler: MockPresistentStreamHandler(),
                ephemeralStreamHandler: MockEphemeralStreamHandler(),
                serverSettings: .defaultSettings,
                clientSettings: .defaultSettings
            )
        )
        let peer2 = try Peer(
            options: PeerOptions<MockStreamHandler>(
                role: .validator,
                listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 0)!,
                genesisHeader: Data32(),
                secretKey: Ed25519.SecretKey(from: Data32(repeating: 2)),
                persistentStreamHandler: handler2,
                ephemeralStreamHandler: MockEphemeralStreamHandler(),
                serverSettings: .defaultSettings,
                clientSettings: .defaultSettings
            )
        )
        try? await Task.sleep(for: .milliseconds(100))

        let connection = try peer1.connect(
            to: peer2.listenAddress(), role: .validator
        )
        try? await Task.sleep(for: .milliseconds(100))

        peer1.broadcast(
            kind: .uniqueA, message: .init(kind: .uniqueA, data: messageData)
        )
        try? await Task.sleep(for: .milliseconds(500))
        let lastReceivedData = await handler2.lastReceivedData
        #expect(lastReceivedData == messageData)

        try? await Task.sleep(for: .milliseconds(100))
        // Simulate abnormal close stream
        let stream = connection.persistentStreams.read { persistentStreams in
            persistentStreams[.uniqueA]
        }
        stream!.close(abort: true)
        // Wait to simulate downtime & reopen up stream 8s
        try? await Task.sleep(for: .milliseconds(8000))
        messageData = [Data("reopen up stream data".utf8)]
        peer1.broadcast(
            kind: .uniqueA, message: .init(kind: .uniqueA, data: messageData)
        )
        try await Task.sleep(for: .milliseconds(2000))
        let lastReceivedData2 = await handler2.lastReceivedData
        #expect(lastReceivedData2 == messageData)
    }

    @Test
    func regularClosedStream() async throws {
        let handler2 = MockPresistentStreamHandler()
        var messageData = [Data("reopen up stream".utf8)]
        let peer1 = try Peer(
            options: PeerOptions<MockStreamHandler>(
                role: .validator,
                listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 0)!,
                genesisHeader: Data32(),
                secretKey: Ed25519.SecretKey(from: Data32(repeating: 1)),
                persistentStreamHandler: MockPresistentStreamHandler(),
                ephemeralStreamHandler: MockEphemeralStreamHandler(),
                serverSettings: .defaultSettings,
                clientSettings: .defaultSettings
            )
        )
        let peer2 = try Peer(
            options: PeerOptions<MockStreamHandler>(
                role: .validator,
                listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 0)!,
                genesisHeader: Data32(),
                secretKey: Ed25519.SecretKey(from: Data32(repeating: 2)),
                persistentStreamHandler: handler2,
                ephemeralStreamHandler: MockEphemeralStreamHandler(),
                serverSettings: .defaultSettings,
                clientSettings: .defaultSettings
            )
        )
        try? await Task.sleep(for: .milliseconds(100))

        let connection = try peer1.connect(
            to: peer2.listenAddress(), role: .validator
        )
        try? await Task.sleep(for: .milliseconds(100))

        peer1.broadcast(
            kind: .uniqueA, message: .init(kind: .uniqueA, data: messageData)
        )
        try? await Task.sleep(for: .milliseconds(500))
        let lastReceivedData = await handler2.lastReceivedData
        #expect(lastReceivedData == messageData)

        try? await Task.sleep(for: .milliseconds(100))
        // Simulate regular close stream
        let stream = connection.persistentStreams.read { persistentStreams in
            persistentStreams[.uniqueA]
        }
        stream!.close(abort: false)
        // Wait to simulate downtime
        try? await Task.sleep(for: .milliseconds(3000))
        messageData = [Data("close up stream".utf8)]
        peer1.broadcast(
            kind: .uniqueA, message: .init(kind: .uniqueA, data: messageData)
        )
        try await Task.sleep(for: .milliseconds(1000))
        let lastReceivedData2 = await handler2.lastReceivedData
        #expect(lastReceivedData2 != messageData)
    }

    @Test
    func concurrentPeerConnection() async throws {
        // setupTestLogger()

        let peer1 = try Peer(
            options: PeerOptions<MockStreamHandler>(
                role: .validator,
                listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 0)!,
                genesisHeader: Data32(),
                secretKey: Ed25519.SecretKey(from: Data32(repeating: 1)),
                persistentStreamHandler: MockPresistentStreamHandler(),
                ephemeralStreamHandler: MockEphemeralStreamHandler(),
                serverSettings: .defaultSettings,
                clientSettings: .defaultSettings
            )
        )
        let peer2 = try Peer(
            options: PeerOptions<MockStreamHandler>(
                role: .validator,
                listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 0)!,
                genesisHeader: Data32(),
                secretKey: Ed25519.SecretKey(from: Data32(repeating: 2)),
                persistentStreamHandler: MockPresistentStreamHandler(),
                ephemeralStreamHandler: MockEphemeralStreamHandler(),
                serverSettings: .defaultSettings,
                clientSettings: .defaultSettings
            )
        )

        try peer1.connect(to: peer2.listenAddress(), role: .validator)
        try peer2.connect(to: peer1.listenAddress(), role: .validator)

        try? await Task.sleep(for: .milliseconds(100))

        let connection1 = try await repeatUntil { peer1.getConnection(publicKey: peer2.publicKey) }
        let connection2 = try await repeatUntil { peer2.getConnection(publicKey: peer1.publicKey) }

        #expect(peer1.peersCount == 1)
        #expect(peer2.peersCount == 1)

        let connections = [connection1, connection2]
        for connection in connections {
            let data = try await connection.request(MockRequest(kind: .typeA, data: [Data("hello world".utf8)]))
            #expect(data == [Data("hello world response".utf8)])
        }
    }

    @Test
    func largeDataRequest() async throws {
        let handler1 = MockPresistentStreamHandler()
        let handler2 = MockPresistentStreamHandler()
        // Define the data size, 5MB
        let dataSize = 10 * 1024 * 1024
        var largeData = Data(capacity: dataSize)

        // Generate random data
        for _ in 0 ..< dataSize {
            largeData.append(UInt8.random(in: 0 ... 255))
        }

        let peer1 = try Peer(
            options: PeerOptions<MockStreamHandler>(
                role: .validator,
                listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 0)!,
                genesisHeader: Data32(),
                secretKey: Ed25519.SecretKey(from: Data32(repeating: 1)),
                persistentStreamHandler: handler1,
                ephemeralStreamHandler: MockEphemeralStreamHandler(),
                serverSettings: .defaultSettings,
                clientSettings: .defaultSettings
            )
        )

        let peer2 = try Peer(
            options: PeerOptions<MockStreamHandler>(
                role: .validator,
                listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 0)!,
                genesisHeader: Data32(),
                secretKey: Ed25519.SecretKey(from: Data32(repeating: 2)),
                persistentStreamHandler: handler2,
                ephemeralStreamHandler: MockEphemeralStreamHandler(),
                serverSettings: .defaultSettings,
                clientSettings: .defaultSettings
            )
        )

        try? await Task.sleep(for: .milliseconds(50))

        let connection1 = try peer1.connect(
            to: peer2.listenAddress(), role: .validator
        )
        try? await Task.sleep(for: .milliseconds(50))

        let receivedData1 = try await connection1.request(
            MockRequest(kind: .typeA, data: [largeData.prefix(dataSize / 2)])
        )
        try? await Task.sleep(for: .milliseconds(100))

        // Verify that the received data matches the original large data
        #expect(receivedData1 == [largeData.prefix(dataSize / 2) + Data(" response".utf8)])
        peer1.broadcast(
            kind: .uniqueA, message: .init(kind: .uniqueA, data: [largeData.prefix(dataSize / 2)])
        )
        try? await Task.sleep(for: .milliseconds(100))

        peer2.broadcast(
            kind: .uniqueB, message: .init(kind: .uniqueB, data: [largeData.prefix(dataSize / 2)])
        )
        // Verify last received data
        try? await Task.sleep(for: .milliseconds(2000))
        await #expect(handler2.lastReceivedData == [largeData.prefix(dataSize / 2)])
        await #expect(handler1.lastReceivedData == [largeData.prefix(dataSize / 2)])
        await #expect(throws: Error.self) {
            _ = try await connection1.request(
                MockRequest(kind: .typeC, data: [largeData])
            )
        }
    }

    @Test
    func connectionNeedToReconnect() async throws {
        let handler2 = MockPresistentStreamHandler()
        let messageData = [Data("Post-recovery message".utf8)]

        let peer1 = try Peer(
            options: PeerOptions<MockStreamHandler>(
                role: .validator,
                listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 0)!,
                genesisHeader: Data32(),
                secretKey: Ed25519.SecretKey(from: Data32(repeating: 1)),
                persistentStreamHandler: MockPresistentStreamHandler(),
                ephemeralStreamHandler: MockEphemeralStreamHandler(),
                serverSettings: .defaultSettings,
                clientSettings: .defaultSettings
            )
        )
        let peer2 = try Peer(
            options: PeerOptions<MockStreamHandler>(
                role: .validator,
                listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 0)!,
                genesisHeader: Data32(),
                secretKey: Ed25519.SecretKey(from: Data32(repeating: 2)),
                persistentStreamHandler: handler2,
                ephemeralStreamHandler: MockEphemeralStreamHandler(),
                serverSettings: .defaultSettings,
                clientSettings: .defaultSettings
            )
        )
        try? await Task.sleep(for: .milliseconds(100))

        let connection = try peer1.connect(
            to: peer2.listenAddress(), role: .validator
        )
        try? await Task.sleep(for: .milliseconds(100))

        let receivedData = try await connection.request(
            MockRequest(kind: .typeA, data: messageData)
        )

        #expect(receivedData == [messageData[0] + Data(" response".utf8)])
        try? await Task.sleep(for: .milliseconds(100))
        // Simulate abnormal shutdown of connections
        try connection.connection.shutdown(errorCode: 1)
        // Wait to simulate downtime & reconnected 3~5s
        try? await Task.sleep(for: .milliseconds(3000))
        peer1.broadcast(
            kind: .uniqueC, message: .init(kind: .uniqueC, data: messageData)
        )
        try await Task.sleep(for: .milliseconds(1000))
        let lastReceivedData = await handler2.lastReceivedData
        #expect(lastReceivedData == messageData)
    }

    @Test
    func connectionNoNeedToReconnect() async throws {
        let handler2 = MockPresistentStreamHandler()
        let messageData = [Data("Post-recovery message".utf8)]

        let peer1 = try Peer(
            options: PeerOptions<MockStreamHandler>(
                role: .validator,
                listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 0)!,
                genesisHeader: Data32(),
                secretKey: Ed25519.SecretKey(from: Data32(repeating: 1)),
                persistentStreamHandler: MockPresistentStreamHandler(),
                ephemeralStreamHandler: MockEphemeralStreamHandler(),
                serverSettings: .defaultSettings,
                clientSettings: .defaultSettings
            )
        )

        let peer2 = try Peer(
            options: PeerOptions<MockStreamHandler>(
                role: .validator,
                listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 0)!,
                genesisHeader: Data32(),
                secretKey: Ed25519.SecretKey(from: Data32(repeating: 2)),
                persistentStreamHandler: handler2,
                ephemeralStreamHandler: MockEphemeralStreamHandler(),
                serverSettings: .defaultSettings,
                clientSettings: .defaultSettings
            )
        )

        try? await Task.sleep(for: .milliseconds(100))

        let connection = try peer1.connect(
            to: peer2.listenAddress(), role: .validator
        )
        try? await Task.sleep(for: .milliseconds(100))
        // Simulate regular shutdown of connections
        connection.close(abort: false)
        // Wait to simulate downtime
        try? await Task.sleep(for: .milliseconds(200))
        peer1.broadcast(
            kind: .uniqueC, message: .init(kind: .uniqueC, data: messageData)
        )
        try? await Task.sleep(for: .milliseconds(1000))
        await #expect(handler2.lastReceivedData == nil)
    }

    @Test
    func connectionManualReconnect() async throws {
        let handler2 = MockPresistentStreamHandler()
        let messageData = [Data("Post-recovery message".utf8)]

        let peer1 = try Peer(
            options: PeerOptions<MockStreamHandler>(
                role: .validator,
                listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 0)!,
                genesisHeader: Data32(),
                secretKey: Ed25519.SecretKey(from: Data32(repeating: 1)),
                persistentStreamHandler: MockPresistentStreamHandler(),
                ephemeralStreamHandler: MockEphemeralStreamHandler(),
                serverSettings: .defaultSettings,
                clientSettings: .defaultSettings
            )
        )

        let peer2 = try Peer(
            options: PeerOptions<MockStreamHandler>(
                role: .validator,
                listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 0)!,
                genesisHeader: Data32(),
                secretKey: Ed25519.SecretKey(from: Data32(repeating: 2)),
                persistentStreamHandler: handler2,
                ephemeralStreamHandler: MockEphemeralStreamHandler(),
                serverSettings: .defaultSettings,
                clientSettings: .defaultSettings
            )
        )

        try? await Task.sleep(for: .milliseconds(100))

        let connection = try peer1.connect(
            to: peer2.listenAddress(), role: .validator
        )
        try? await Task.sleep(for: .milliseconds(100))

        let receivedData = try await connection.request(
            MockRequest(kind: .typeA, data: messageData)
        )

        #expect(receivedData == [messageData[0] + Data(" response".utf8)])
        try? await Task.sleep(for: .milliseconds(100))
        // Simulate a peer failure by disconnecting one peer
        try connection.connection.shutdown()
        // Wait to simulate downtime
        try? await Task.sleep(for: .milliseconds(200))
        // Reconnect the failing peer
        let reconnection = try peer1.connect(
            to: peer2.listenAddress(),
            role: .validator
        )
        try? await Task.sleep(for: .milliseconds(100))
        let recoverData = try await reconnection.request(
            MockRequest(kind: .typeA, data: messageData)
        )
        try? await Task.sleep(for: .milliseconds(100))
        #expect(recoverData == [messageData[0] + Data(" response".utf8)])
        peer1.broadcast(
            kind: .uniqueC, message: .init(kind: .uniqueC, data: recoverData)
        )
        try? await Task.sleep(for: .milliseconds(1000))
        await #expect(handler2.lastReceivedData == recoverData)
    }

    @Test
    func peerBroadcast() async throws {
        let handler1 = MockPresistentStreamHandler()
        let handler2 = MockPresistentStreamHandler()

        let peer1 = try Peer(
            options: PeerOptions<MockStreamHandler>(
                role: .validator,
                listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 0)!,
                genesisHeader: Data32(),
                secretKey: Ed25519.SecretKey(from: Data32(repeating: 1)),
                persistentStreamHandler: handler1,
                ephemeralStreamHandler: MockEphemeralStreamHandler(),
                serverSettings: .defaultSettings,
                clientSettings: .defaultSettings
            )
        )
        let peer2 = try Peer(
            options: PeerOptions<MockStreamHandler>(
                role: .validator,
                listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 0)!,
                genesisHeader: Data32(),
                secretKey: Ed25519.SecretKey(from: Data32(repeating: 2)),
                persistentStreamHandler: handler2,
                ephemeralStreamHandler: MockEphemeralStreamHandler(),
                serverSettings: .defaultSettings,
                clientSettings: .defaultSettings
            )
        )

        _ = try peer1.connect(
            to: peer2.listenAddress(), role: .validator
        )

        try? await Task.sleep(for: .milliseconds(500))

        peer1.broadcast(
            kind: .uniqueA, message: .init(kind: .uniqueA, data: [Data("hello world".utf8)])
        )

        peer2.broadcast(
            kind: .uniqueB, message: .init(kind: .uniqueB, data: [Data("I am jam".utf8)])
        )
        // Verify last received data
        try? await Task.sleep(for: .milliseconds(500))
        await #expect(handler2.lastReceivedData == [Data("hello world".utf8)])
        await #expect(handler1.lastReceivedData == [Data("I am jam".utf8)])
    }

    @Test
    func peerRequest() async throws {
        let peer1 = try Peer(
            options: PeerOptions<MockStreamHandler>(
                role: .validator,
                listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 0)!,
                genesisHeader: Data32(),
                secretKey: Ed25519.SecretKey(from: Data32(repeating: 1)),
                persistentStreamHandler: MockPresistentStreamHandler(),
                ephemeralStreamHandler: MockEphemeralStreamHandler(),
                serverSettings: .defaultSettings,
                clientSettings: .defaultSettings
            )
        )
        let peer2 = try Peer(
            options: PeerOptions<MockStreamHandler>(
                role: .validator,
                listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 0)!,
                genesisHeader: Data32(),
                secretKey: Ed25519.SecretKey(from: Data32(repeating: 2)),
                persistentStreamHandler: MockPresistentStreamHandler(),
                ephemeralStreamHandler: MockEphemeralStreamHandler(),
                serverSettings: .defaultSettings,
                clientSettings: .defaultSettings
            )
        )

        let connection1 = try peer1.connect(
            to: peer2.listenAddress(), role: .validator
        )

        let dataList1 = try await connection1.request(
            MockRequest(kind: .typeA, data: [Data("hello world".utf8)])
        )
        try? await Task.sleep(for: .milliseconds(100))
        #expect(dataList1 == [Data("hello world response".utf8)])
    }

    @Test
    func multiplePeerBroadcast() async throws {
        var peers: [Peer<MockStreamHandler>] = []
        var handlers: [MockPresistentStreamHandler] = []
        // Create 100 peer nodes
        for i in 0 ..< 100 {
            let handler = MockPresistentStreamHandler()
            handlers.append(handler)
            let peer = try Peer(
                options: PeerOptions<MockStreamHandler>(
                    role: .builder,
                    listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 0)!,
                    genesisHeader: Data32(),
                    secretKey: Ed25519.SecretKey(from: Data32(repeating: UInt8(i))),
                    persistentStreamHandler: handler,
                    ephemeralStreamHandler: MockEphemeralStreamHandler(),
                    serverSettings: .defaultSettings,
                    clientSettings: .defaultSettings
                )
            )
            peers.append(peer)
        }

        // Make some connections
        for i in 0 ..< peers.count {
            let peer = peers[i]
            let otherPeer = peers[(i + 1) % peers.count]
            let conn1 = try peer.connect(
                to: otherPeer.listenAddress(),
                role: .validator
            )
            let otherPeer2 = peers[(i + 2) % peers.count]
            let conn2 = try peer.connect(
                to: otherPeer2.listenAddress(),
                role: .validator
            )

            try await conn1.ready()
            try await conn2.ready()
        }

        // Broadcast a message from each peer
        for (i, peer) in peers.enumerated() {
            let message = MockRequest(
                kind: i % 2 == 0 ? UniquePresistentStreamKind.uniqueA : UniquePresistentStreamKind.uniqueB,
                data: [Data("Message from peer \(i)".utf8)]
            )
            peer.broadcast(kind: message.kind, message: message)
            try? await Task.sleep(for: .milliseconds(50))
        }

        // Wait for message propagation
        try? await Task.sleep(for: .milliseconds(1000))

        // everyone should receive two messages
        for (idx, handler) in handlers.enumerated() {
            #expect(await handler.receivedData.count == 4) // 2 outgoing + 2 incoming
            #expect(await handler.receivedData.contains([Data("Message from peer \((idx + 99) % 100)".utf8)]))
            #expect(await handler.receivedData.contains([Data("Message from peer \((idx + 98) % 100)".utf8)]))
            #expect(await handler.receivedData.contains([Data("Message from peer \((idx + 1) % 100)".utf8)]))
            #expect(await handler.receivedData.contains([Data("Message from peer \((idx + 2) % 100)".utf8)]))
        }
    }

    @Test
    func multiplePeerRequest() async throws {
        var peers: [Peer<MockStreamHandler>] = []

        // Create 100 peer nodes
        for i in 0 ..< 100 {
            let peer = try Peer(
                options: PeerOptions<MockStreamHandler>(
                    role: .builder,
                    listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 0)!,
                    genesisHeader: Data32(),
                    secretKey: Ed25519.SecretKey(from: Data32(repeating: UInt8(i))),
                    persistentStreamHandler: MockPresistentStreamHandler(),
                    ephemeralStreamHandler: MockEphemeralStreamHandler(),
                    serverSettings: .defaultSettings,
                    clientSettings: .defaultSettings
                )
            )
            peers.append(peer)
        }

        // Wait for peers to initialize
        try? await Task.sleep(for: .milliseconds(50))

        var tasks = [Task<Void, Error>]()
        // Test request-response by having each peer request from the next peer
        for i in 0 ..< 100 {
            tasks.append(Task {
                let messageData = [Data("Request from peer \(i)".utf8)]
                let otherPeer = peers[(i + 1) % peers.count]
                let type = (i + 1) % 2 == 0 ? EphemeralStreamKind.typeA : EphemeralStreamKind.typeB
                let response = try await peers[i].connect(
                    to: otherPeer.listenAddress(),
                    role: .validator
                ).request(MockRequest(kind: type, data: messageData))
                try? await Task.sleep(for: .milliseconds(100))
                #expect(response == [messageData[0] + Data(" response".utf8)], "Peer \(i) should receive correct response")
            })
        }

        for task in tasks {
            try await task.value
        }
    }

    @Test
    func highConcurrentRequest() async throws {
        var peers: [Peer<MockStreamHandler>] = []
        let peersCount = 50
        // Create peers
        for i in 0 ..< peersCount {
            let peer = try Peer(
                options: PeerOptions<MockStreamHandler>(
                    role: .validator,
                    listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 0)!,
                    genesisHeader: Data32(),
                    secretKey: Ed25519.SecretKey(from: Data32(repeating: UInt8(i))),
                    persistentStreamHandler: MockPresistentStreamHandler(),
                    ephemeralStreamHandler: MockEphemeralStreamHandler(),
                    serverSettings: .defaultSettings,
                    clientSettings: .defaultSettings
                )
            )
            peers.append(peer)
        }

        var connections = [Connection<MockStreamHandler>]()
        for i in 0 ..< peersCount {
            let peer = peers[i]
            for j in i + 1 ..< peersCount {
                let otherPeer = peers[j]
                let conn = try peer.connect(
                    to: otherPeer.listenAddress(),
                    role: .validator
                )
                connections.append(conn)
            }
        }

        for conn in connections {
            try await conn.ready()
        }

        // Send multiple requests from each peer
        for (idx, peer) in peers.enumerated() {
            let tasks = (1 ..< peersCount).map { i in
                let other = peers[(idx + i) % peers.count]
                return Task {
                    let type = i % 2 == 0 ? EphemeralStreamKind.typeA : EphemeralStreamKind.typeB
                    let messageData = [Data("Concurrent request \(i)".utf8)]
                    let response = try await peer.getConnection(
                        publicKey: other.publicKey
                    )
                    .unwrap()
                    .request(MockRequest(kind: type, data: messageData))
                    try? await Task.sleep(for: .milliseconds(50))
                    #expect(response == [messageData[0] + Data(" response".utf8)], "Peer should receive correct response")
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
        var handles: [MockPresistentStreamHandler] = []

        // Create 50 peers with unique addresses
        for i in 0 ..< 50 {
            let handle = MockPresistentStreamHandler()
            let peer = try Peer(
                options: PeerOptions<MockStreamHandler>(
                    role: .validator,
                    listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 0)!,
                    genesisHeader: Data32(),
                    secretKey: Ed25519.SecretKey(from: Data32(repeating: UInt8(i))),
                    persistentStreamHandler: handle,
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
            let peer = peers[i]
            for j in 0 ..< peers.count where i > j {
                let otherPeer = peers[j]
                let conn = try peer.connect(
                    to: otherPeer.listenAddress(),
                    role: .validator
                )

                try await conn.ready()
            }
        }

        let centralPeer = peers[0]
        let messagedata = [Data("Sync message".utf8)]
        centralPeer.broadcast(kind: .uniqueA, message: MockRequest(kind: .uniqueA, data: messagedata))

        // Check that each peer received the broadcast
        for i in 1 ..< handles.count {
            let receivedData = try await repeatUntil { await handles[i].lastReceivedData }
            #expect(receivedData == messagedata, "Handle should have received the broadcast message")
        }
    }
}
