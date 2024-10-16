import Foundation
import MsQuicSwift
import Testing
import Utils

@testable import Networking

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
}
