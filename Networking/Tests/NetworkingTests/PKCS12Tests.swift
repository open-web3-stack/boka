import Foundation
import MsQuicSwift
import Testing
import Utils

@testable import Networking

let badCertData =
    Data(
        // swiftlint:disable:next line_length
        fromHexString: "308203960201033082034c06092a864886f70d010701a082033d04820339308203353082023a06092a864886f70d010706a082022b308202270201003082022006092a864886f70d010701305f06092a864886f70d01050d3052303106092a864886f70d01050c30240410c170b7f541c254f19415eec66bf29ce002020800300c06082a864886f70d02090500301d060960864801650304012a04104c055a3b226f863da99d9c9189e5c6d4808201b0fb5b53346c0b99c5a7e825dcdeedd3e5d8f525b082164e2cf0ec5e9ecd56eb5dbeda7afbae97be39fdae32774633411fc0b879e15b777e5938aa0166f3e6f88f45cbf3a5b1b03a903a1a137c15e7a2be39ec90108e58e5137529b1850e5606f17ded7ffa2f3531149939f936048194a837e4339dcc73dbaeab09b35a27898e156490aeeca2ab2ad282e0a79cecd07b7288e764e708d901a3edef456c28d48c176f8979c4bb377160dfeacf19b53a7ecdd874ef21dbbd71f46c5d099c824e19faf4e12a468d3c4036bcead4a8722fff840fd0136f9a4d4f885a038ead5e8db80df9eebc4611d9415741eb5768b12c262d19ca83201bfe644a6a0a74b2ed2b75abbe7e298c191a5e24d06ab0c5b1d31994a88ec7c94c583ddc3ed80209ee96a8b3fc447ae17b9e6f1dbb346d01b386203ddec4db6cb7872d7c0118497dcc4c86155c4e304f0b42e6f8a99ad6332a25fd614f38f70e5351efcbb3e61850df143dd0bfaced69ceb47ec6cafd6d116945d2e872d75f4d1dd456f5edc71def3a90dda99ce18edb72b67ca38e83dbaf6e2be1cbae790479aa5bd469a11c5b2ec70d6143bece7b72aeb949b1dfded6354641fe0d3081f406092a864886f70d010701a081e60481e33081e03081dd060b2a864886f70d010c0a0102a081a63081a3305f06092a864886f70d01050d3052303106092a864886f70d01050c302404105babdc09b74da772643b9efce0419a7d02020800300c06082a864886f70d02090500301d060960864801650304012a0410bdedcee2545a81c04ee14603e5ee9378044061a6a3228aeeb6f95677894b2e7e582c95a0527140edfeb43f199f13a6bbb4ede8f630b30a664e1e740c28ddbce3e317243cfc8c3ae283b834ce77ce9a1c963b3125302306092a864886f70d01091531160414c4561932b37ec791f3a8d10dfbe71211aef56d6f30413031300d0609608648016503040201050004209fba7a4e53ab05c5d40a43f70afd6bb6d3765d7b9e033f3de563c902626f6a46040805f3adf78a4477ff02020800"
    )!
struct PKCS12Tests {
    @Test func generate() async throws {
        let privateKey = try Ed25519.SecretKey(from: Data32())
        let cert = try generateSelfSignedCertificate(privateKey: privateKey)
        #expect(cert.count > 0)

        let registration = try QuicRegistration()

        let serverHandler = MockQuicEventHandler()
        let clientHandler = MockQuicEventHandler()

        // create listener

        let quicSettings = QuicSettings.defaultSettings
        let serverConfiguration = try QuicConfiguration(
            registration: registration,
            pkcs12: cert,
            alpns: [Data("testalpn".utf8)],
            client: false,
            settings: quicSettings
        )

        let listener = try QuicListener(
            handler: serverHandler,
            registration: registration,
            configuration: serverConfiguration,
            listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 0),
            alpns: [Data("testalpn".utf8)]
        )

        let listenAddress = try listener.listenAddress()

        // create connection to listener

        let clientConfiguration = try QuicConfiguration(
            registration: registration,
            pkcs12: cert,
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

        try? await Task.sleep(for: .milliseconds(50))

        let clientData = clientHandler.events.value.compactMap {
            switch $0 {
            case let .shouldOpen(_, certificate):
                certificate as Data?
            default:
                nil
            }
        }

        #expect(clientData.first!.count > 0)

        let serverData = serverHandler.events.value.compactMap {
            switch $0 {
            case let .shouldOpen(_, certificate):
                certificate as Data?
            default:
                nil
            }
        }

        #expect(serverData.first!.count > 0)
    }

    @Test func clientRejectsBadServerCert() async throws {
        let privateKey = try Ed25519.SecretKey(from: Data32())
        let cert = try generateSelfSignedCertificate(privateKey: privateKey)

        let registration = try QuicRegistration()

        let serverHandler = MockQuicEventHandler()
        let clientHandler = MockQuicEventHandler()

        let quicSettings = QuicSettings.defaultSettings
        let serverConfiguration = try QuicConfiguration(
            registration: registration,
            pkcs12: badCertData, // Use bad certificate
            alpns: [Data("testalpn".utf8)],
            client: false,
            settings: quicSettings
        )

        let listener = try QuicListener(
            handler: serverHandler,
            registration: registration,
            configuration: serverConfiguration,
            listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 0),
            alpns: [Data("testalpn".utf8)]
        )

        let listenAddress = try listener.listenAddress()

        let clientConfiguration = try QuicConfiguration(
            registration: registration,
            pkcs12: cert,
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

        try? await Task.sleep(for: .milliseconds(100))

        let clientData = clientHandler.events.value.compactMap {
            switch $0 {
            case let .shouldOpen(_, certificate):
                certificate as Data?
            default:
                nil
            }
        }

        #expect(clientData.first!.count > 0)

        let serverData = serverHandler.events.value.compactMap {
            switch $0 {
            case let .shouldOpen(connection, certificate):
                certificate as Data?
            default:
                nil
            }
        }

        #expect(serverData.first!.count > 0)
    }

    @Test func serverRejectsBadClientCert() async throws {
        let privateKey = try Ed25519.SecretKey(from: Data32())
        let badCert = Data() // Simulate a bad certificate
        let cert = try generateSelfSignedCertificate(privateKey: privateKey)
        let registration = try QuicRegistration()

        let serverHandler = MockQuicEventHandler()
        let clientHandler = MockQuicEventHandler()

        let quicSettings = QuicSettings.defaultSettings
        let serverConfiguration = try QuicConfiguration(
            registration: registration,
            pkcs12: cert,
            alpns: [Data("testalpn".utf8)],
            client: false,
            settings: quicSettings
        )

        let listener = try QuicListener(
            handler: serverHandler,
            registration: registration,
            configuration: serverConfiguration,
            listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 0),
            alpns: [Data("testalpn".utf8)]
        )

        let listenAddress = try listener.listenAddress()

        let clientConfiguration = try QuicConfiguration(
            registration: registration,
            pkcs12: badCert, // Use bad certificate
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

        let clientData = clientHandler.events.value.compactMap {
            switch $0 {
            case let .shouldOpen(_, certificate):
                certificate as Data?
            default:
                nil
            }
        }

        #expect(clientData.first!.count > 0)

        let serverData = serverHandler.events.value.compactMap {
            switch $0 {
            case let .shouldOpen(_, certificate):
                certificate as Data?
            default:
                nil
            }
        }

        #expect(serverData.first!.count > 0)
    }
}
