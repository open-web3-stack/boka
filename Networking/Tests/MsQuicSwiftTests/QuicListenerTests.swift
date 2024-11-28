import Foundation
import Testing
import TracingUtils
import Utils

@testable import MsQuicSwift

// to generate one:
// openssl genpkey -algorithm ED25519 -out private_key.pem
// openssl req -new -x509 -key private_key.pem -out certificate.pem -days 365 -subj "/CN=YourCommonName"
// openssl pkcs12 -export -out certificate.p12 -inkey private_key.pem -in certificate.pem
let pkcs12Data =
    Data(
        fromHexString: """
        308203960201033082034c06092a864886f70d010701a082033d04820339308203353082023a06092a864886f70d010706a082022b30820227020100\
        3082022006092a864886f70d010701305f06092a864886f70d01050d3052303106092a864886f70d01050c30240410c170b7f541c254f19415eec66bf\
        29ce002020800300c06082a864886f70d02090500301d060960864801650304012a04104c055a3b226f863da99d9c9189e5c6d4808201b0fb5b53346c\
        0b99c5a7e825dcdeedd3e5d8f525b082164e2cf0ec5e9ecd56eb5dbeda7afbae97be39fdae32774633411fc0b879e15b777e5938aa0166f3e6f88f45c\
        bf3a5b1b03a903a1a137c15e7a2be39ec90108e58e5137529b1850e5606f17ded7ffa2f3531149939f936048194a837e4339dcc73dbaeab09b35a2789\
        8e156490aeeca2ab2ad282e0a79cecd07b7288e764e708d901a3edef456c28d48c176f8979c4bb377160dfeacf19b53a7ecdd874ef21dbbd71f46c5d0\
        99c824e19faf4e12a468d3c4036bcead4a8722fff840fd0136f9a4d4f885a038ead5e8db80df9eebc4611d9415741eb5768b12c262d19ca83201bfe64\
        4a6a0a74b2ed2b75abbe7e298c191a5e24d06ab0c5b1d31994a88ec7c94c583ddc3ed80209ee96a8b3fc447ae17b9e6f1dbb346d01b386203ddec4db6\
        cb7872d7c0118497dcc4c86155c4e304f0b42e6f8a99ad6332a25fd614f38f70e5351efcbb3e61850df143dd0bfaced69ceb47ec6cafd6d116945d2e8\
        72d75f4d1dd456f5edc71def3a90dda99ce18edb72b67ca38e83dbaf6e2be1cbae790479aa5bd469a11c5b2ec70d6143bece7b72aeb949b1dfded6354\
        641fe0d3081f406092a864886f70d010701a081e60481e33081e03081dd060b2a864886f70d010c0a0102a081a63081a3305f06092a864886f70d0105\
        0d3052303106092a864886f70d01050c302404105babdc09b74da772643b9efce0419a7d02020800300c06082a864886f70d02090500301d06096086\
        4801650304012a0410bdedcee2545a81c04ee14603e5ee9378044061a6a3228aeeb6f95677894b2e7e582c95a0527140edfeb43f199f13a6bbb4ede8f\
        630b30a664e1e740c28ddbce3e317243cfc8c3ae283b834ce77ce9a1c963b3125302306092a864886f70d01091531160414c4561932b37ec791f3a8d1\
        0dfbe71211aef56d6f30413031300d0609608648016503040201050004209fba7a4e53ab05c5d40a43f70afd6bb6d3765d7b9e033f3de563c902626f6\
        a46040805f3adf78a4477ff02020800
        """
    )!

struct QuicListenerTests {
    let registration: QuicRegistration

    init() throws {
        // setupTestLogger()

        registration = try QuicRegistration()
    }

    final class MockQuicEventHandler: QuicEventHandler {
        enum EventType {
            case newConnection(listener: QuicListener, connection: QuicConnection, info: ConnectionInfo)
            case shouldOpen(connection: QuicConnection, certificate: Data?)
            case connected(connection: QuicConnection)
            case shutdownInitiated(connection: QuicConnection, reason: ConnectionCloseReason)
            case shutdownComplete(connection: QuicConnection)
            case streamStarted(connection: QuicConnection, stream: QuicStream)
            case dataReceived(stream: QuicStream, data: Data?)
            case closed(stream: QuicStream, status: QuicStatus, code: QuicErrorCode)
        }

        let events: ThreadSafeContainer<[EventType]> = .init([])

        init() {}

        func newConnection(
            _ listener: QuicListener, connection: QuicConnection, info: ConnectionInfo
        ) -> QuicStatus {
            events.write { events in
                events.append(.newConnection(listener: listener, connection: connection, info: info))
            }
            return .code(.success)
        }

        func shouldOpen(_ connection: QuicConnection, certificate: Data?) -> QuicStatus {
            events.write { events in
                events.append(.shouldOpen(connection: connection, certificate: certificate))
            }
            return .code(.success)
        }

        func connected(_ connection: QuicConnection) {
            events.write { events in
                events.append(.connected(connection: connection))
            }
        }

        func streamStarted(_ connect: QuicConnection, stream: QuicStream) {
            events.write { events in
                events.append(.streamStarted(connection: connect, stream: stream))
            }
        }

        func dataReceived(_ stream: QuicStream, data: Data?) {
            events.write { events in
                events.append(.dataReceived(stream: stream, data: data))
            }
        }
    }

    final class EmptyQuicEventHandler: QuicEventHandler {}

    @Test
    func emptyQuicEventHandler() async throws {
        let serverHandler = MockQuicEventHandler()
        let clientHandler = EmptyQuicEventHandler()

        // create listener

        let quicSettings = QuicSettings.defaultSettings
        let serverConfiguration = try QuicConfiguration(
            registration: registration,
            pkcs12: pkcs12Data,
            alpns: [Data("testalpn".utf8)],
            client: false,
            settings: quicSettings
        )

        let listener = try QuicListener(
            handler: serverHandler,
            registration: registration,
            configuration: serverConfiguration,
            listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 0)!,
            alpns: [Data("testalpn".utf8)]
        )

        let listenAddress = try listener.listenAddress()
        let (ipAddress, port) = listenAddress.getAddressAndPort()
        #expect(ipAddress == "127.0.0.1")
        #expect(port != 0)

        // create connection to listener

        let clientConfiguration = try QuicConfiguration(
            registration: registration,
            pkcs12: pkcs12Data,
            alpns: [Data("testalpn".utf8)],
            client: true,
            settings: quicSettings
        )

        let clientConnection = try QuicConnection(
            handler: clientHandler,
            registration: registration,
            configuration: clientConfiguration
        )

        try clientConnection.connect(to: listenAddress)

        let stream1 = try clientConnection.createStream()

        try stream1.send(data: Data("test data 1".utf8))

        try? await Task.sleep(for: .milliseconds(100))
        let (serverConnection, info) = serverHandler.events.value.compactMap {
            switch $0 {
            case let .newConnection(_, connection, info):
                (connection, info) as (QuicConnection, ConnectionInfo)?
            default:
                nil
            }
        }.first!

        let (ipAddress2, _) = info.remoteAddress.getAddressAndPort()

        #expect(info.negotiatedAlpn == Data("testalpn".utf8))
        #expect(info.serverName == "127.0.0.1")
        #expect(info.localAddress == listenAddress)
        #expect(ipAddress2 == "127.0.0.1")

        let stream2 = try serverConnection.createStream()
        try stream2.send(data: Data("other test data 2".utf8))

        try? await Task.sleep(for: .milliseconds(100))
        let receivedData = serverHandler.events.value.compactMap {
            switch $0 {
            case let .dataReceived(_, data):
                data
            default:
                nil
            }
        }

        #expect(receivedData.count == 1)
        #expect(receivedData[0] == Data("test data 1".utf8))
        try clientConnection.shutdown()
        try? await Task.sleep(for: .milliseconds(1000))
        #expect(throws: Error.self) {
            try serverConnection.connect(to: info.remoteAddress)
        }
        #expect(throws: Error.self) {
            _ = try clientConnection.getRemoteAddress()
        }
    }

    @Test
    func connectAndSendReceive() async throws {
        let serverHandler = MockQuicEventHandler()
        let clientHandler = MockQuicEventHandler()

        // create listener

        let quicSettings = QuicSettings.defaultSettings
        let serverConfiguration = try QuicConfiguration(
            registration: registration,
            pkcs12: pkcs12Data,
            alpns: [Data("testalpn".utf8)],
            client: false,
            settings: quicSettings
        )

        let listener = try QuicListener(
            handler: serverHandler,
            registration: registration,
            configuration: serverConfiguration,
            listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 0)!,
            alpns: [Data("testalpn".utf8)]
        )

        let listenAddress = try listener.listenAddress()
        let (ipAddress, port) = listenAddress.getAddressAndPort()
        #expect(ipAddress == "127.0.0.1")
        #expect(port != 0)

        // create connection to listener

        let clientConfiguration = try QuicConfiguration(
            registration: registration,
            pkcs12: pkcs12Data,
            alpns: [Data("testalpn".utf8)],
            client: true,
            settings: quicSettings
        )

        let clientConnection = try QuicConnection(
            handler: clientHandler,
            registration: registration,
            configuration: clientConfiguration
        )

        try clientConnection.connect(to: listenAddress)

        let stream1 = try clientConnection.createStream()

        try stream1.send(data: Data("test data 1".utf8))

        try? await Task.sleep(for: .milliseconds(100))
        let (serverConnection, info) = serverHandler.events.value.compactMap {
            switch $0 {
            case let .newConnection(_, connection, info):
                (connection, info) as (QuicConnection, ConnectionInfo)?
            default:
                nil
            }
        }.first!

        let (ipAddress2, _) = info.remoteAddress.getAddressAndPort()

        #expect(info.negotiatedAlpn == Data("testalpn".utf8))
        #expect(info.serverName == "127.0.0.1")
        #expect(info.localAddress == listenAddress)
        #expect(ipAddress2 == "127.0.0.1")

        let stream2 = try serverConnection.createStream()
        try stream2.send(data: Data("other test data 2".utf8))

        try? await Task.sleep(for: .milliseconds(100))
        let remoteStream1 = clientHandler.events.value.compactMap {
            switch $0 {
            case let .streamStarted(_, stream):
                stream as QuicStream?
            default:
                nil
            }
        }.first!
        try remoteStream1.send(data: Data("replay to 1".utf8))

        try? await Task.sleep(for: .milliseconds(100))
        let remoteStream2 = serverHandler.events.value.compactMap {
            switch $0 {
            case let .streamStarted(_, stream):
                stream as QuicStream?
            default:
                nil
            }
        }.first!
        try remoteStream2.send(data: Data("another replay to 2".utf8))

        try? await Task.sleep(for: .milliseconds(200))
        let receivedData = serverHandler.events.value.compactMap {
            switch $0 {
            case let .dataReceived(_, data):
                data
            default:
                nil
            }
        }
        #expect(receivedData.count == 2)
        #expect(receivedData[0] == Data("test data 1".utf8))
        #expect(receivedData[1] == Data("replay to 1".utf8))

        let receivedData2 = clientHandler.events.value.compactMap {
            switch $0 {
            case let .dataReceived(_, data):
                data
            default:
                nil
            }
        }
        #expect(receivedData2.count == 2)
        #expect(receivedData2[0] == Data("other test data 2".utf8))
        #expect(receivedData2[1] == Data("another replay to 2".utf8))
    }
}
