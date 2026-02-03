import Foundation
import MsQuicSwift
@testable import Networking
import Testing
import Utils

struct PKCS12Tests {
    @Test func invalidParseCertificate() throws {
        #expect(throws: CryptoError.self) {
            _ = try parseCertificate(data: Data("wrong cert data".utf8), type: .p12)
        }
    }

    @Test func vailidParseP12Certificate() throws {
        let privateKey = try Ed25519.SecretKey(from: Data32())
        let cert = try generateSelfSignedCertificate(privateKey: privateKey)
        let (publicKey, alternativeName) = try parseCertificate(data: cert, type: .p12)
        #expect(alternativeName == generateSubjectAlternativeName(publicKey: privateKey.publicKey))
        #expect(Data32(publicKey) == privateKey.publicKey.data)
    }

    @Test func generate() async throws {
        let privateKey = try Ed25519.SecretKey(from: Data32())
        let cert = try generateSelfSignedCertificate(privateKey: privateKey)
        #expect(cert.count > 0)

        let registration = try QuicRegistration()

        let serverHandler = MockPeerEventTests.MockPeerEventHandler()
        let clientHandler = MockPeerEventTests.MockPeerEventHandler()

        // create listener

        let quicSettings = QuicSettings.defaultSettings
        let serverConfiguration = try QuicConfiguration(
            registration: registration,
            pkcs12: cert,
            alpns: [Data("testalpn".utf8)],
            client: false,
            settings: quicSettings,
        )

        let listener = try QuicListener(
            handler: serverHandler,
            registration: registration,
            configuration: serverConfiguration,
            listenAddress: #require(NetAddr(ipAddress: "127.0.0.1", port: 0)),
            alpns: [Data("testalpn".utf8)],
        )

        let listenAddress = try listener.listenAddress()

        // create connection to listener

        let clientConfiguration = try QuicConfiguration(
            registration: registration,
            pkcs12: cert,
            alpns: [Data("testalpn".utf8)],
            client: true,
            settings: quicSettings,
        )

        let clientConnection = try QuicConnection(
            handler: clientHandler,
            registration: registration,
            configuration: clientConfiguration,
        )

        try clientConnection.connect(to: listenAddress)

        try? await Task.sleep(for: .milliseconds(50))

        let clientConn = try #require(clientHandler.events.value.compactMap {
            if case let .connected(connection: connection) = $0 {
                return connection
            }
            return nil
        }.first)
        #expect(clientConn != nil)

        let serverConn = try #require(serverHandler.events.value.compactMap {
            if case let .connected(connection: connection) = $0 {
                return connection
            }
            return nil
        }.first)
        #expect(serverConn != nil)
    }
}
