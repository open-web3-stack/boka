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

    struct MockMessageDecoder: MessageDecoder {
        typealias Message = MockMessage

        func decode(data: Data) throws -> Message {
            MockMessage(data: data)
        }

        func finish() -> Data? {
            print("MockMessageDecoder finish")
            return nil
        }
    }

    struct MockEphemeralStreamHandler: EphemeralStreamHandler {
        typealias StreamKind = EphemeralStreamKind
        typealias Request = MockRequest<EphemeralStreamKind>

        func createDecoder(kind _: StreamKind) -> any MessageDecoder<Request> {
            return MockMessageDecoder() as! any MessageDecoder<Request>
        }

        // deal with data
        func handle(connection _: any ConnectionInfoProtocol, request _: Request) async throws -> Data {
            print("MockEphemeralStreamHandler handle")
            return Data()
        }
    }

    struct MockPresentStreamHandler: PresistentStreamHandler {
        func streamOpened(
            connection _: any Networking.ConnectionInfoProtocol,
            stream _: any Networking.StreamProtocol, kind _: PeerTests.UniquePresistentStreamKind
        ) async throws {
            print("streamOpened")
        }

        func handle(
            connection _: any Networking.ConnectionInfoProtocol,
            message _: PeerTests.MockRequest<PeerTests.UniquePresistentStreamKind>
        ) async throws {
            print("handle")
        }

        typealias StreamKind = UniquePresistentStreamKind
        typealias Request = MockRequest<UniquePresistentStreamKind>

        func createDecoder(kind _: StreamKind) -> any MessageDecoder<Request> {
            return MockMessageDecoder() as! any MessageDecoder<Request>
        }

        func handle(connection _: any ConnectionInfoProtocol, request _: Request) async throws -> Data {
            Data()
        }
    }

    struct MockStreamHandler: StreamHandler {
        typealias PresistentHandler = MockPresentStreamHandler

        typealias EphemeralHandler = MockEphemeralStreamHandler
    }

    @Test
    func peerInit() async throws {
        let peer1 = try Peer(
            options: PeerOptions<MockStreamHandler>(
                mode: .validator,
                listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 8081)!,
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
                mode: .validator,
                listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 8082)!,
                genesisHeader: Data32(),
                secretKey: Ed25519.SecretKey(from: Data32()),
                presistentStreamHandler: MockPresentStreamHandler(),
                ephemeralStreamHandler: MockEphemeralStreamHandler(),
                serverSettings: .defaultSettings,
                clientSettings: .defaultSettings
            )
        )
        let connection = try peer1.connect(
            to: NetAddr(ipAddress: "127.0.0.1", port: 8082)!, mode: .validator
        )
        try? await Task.sleep(for: .seconds(2))
        let data = try await connection.request(MockRequest(kind: .typeA, data: Data("hello world".utf8)))
        if let string = String(data: data, encoding: .utf8) {
            print(string)
        } else {
            print("Failed to convert Data to String")
        }
        try? await Task.sleep(for: .seconds(10))
    }
}
