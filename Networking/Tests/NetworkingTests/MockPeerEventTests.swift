import AsyncChannels
import Foundation
import Logging
import MsQuicSwift
import Testing
import Utils

@testable import Networking

final class MockPeerEventTests {
    final class MockPeerEventHandler: QuicEventHandler {
        enum EventType {
            case newConnection(listener: QuicListener, connection: QuicConnection, info: ConnectionInfo)
            case shouldOpen(connection: QuicConnection, certificate: Data?)
            case connected(connection: QuicConnection)
            case shutdownInitiated(connection: QuicConnection, reason: ConnectionCloseReason)
            case streamStarted(connection: QuicConnection, stream: QuicStream)
            case dataReceived(stream: QuicStream, data: Data?)
            case closed(stream: QuicStream, status: QuicStatus, code: QuicErrorCode)
        }

        let logger: Logger
        let channel: Channel<Data> = .init(capacity: 100)
        let events: ThreadSafeContainer<[EventType]> = .init([])
        let resendStates: ThreadSafeContainer<[UniqueId: BackoffState]> = .init([:])
        let maxRetryAttempts = 5
        let isBackpressureEnabled: Bool
        init(_ isBackpressureEnabled: Bool = false) {
            self.isBackpressureEnabled = isBackpressureEnabled
            logger = Logger(label: "MockPeerEventHandler")
        }

        private func backpressure(_ data: Data, on stream: QuicStream) {
            logger.info("backpressure for stream: \(stream.id)")
            let state = resendStates.read { reconnectStates in
                reconnectStates[stream.id] ?? .init()
            }

            do {
                let windowSize = try stream.getFlowControlWindow()
                logger.info("backpressure: \(stream.id) window size: \(windowSize)")
                guard state.attempt < maxRetryAttempts else {
                    logger.warning("backpressure: \(stream.id) reached max retry attempts")
                    try? stream.adjustFlowControl(recvBufferSize: Int(Int16.max))
                    return
                }
                try stream.adjustFlowControl(recvBufferSize: windowSize >> 1)
                resendStates.write { resendStates in
                    if var state = resendStates[stream.id] {
                        state.applyBackoff()
                        resendStates[stream.id] = state
                    }
                }
                Task {
                    try await Task.sleep(for: .seconds(state.delay))
                    if !channel.syncSend(data) {
                        logger.warning("stream \(stream.id) is full")
                        backpressure(data, on: stream)
                    } else {
                        try stream.adjustFlowControl(recvBufferSize: Int(Int16.max))
                        resendStates.write { states in
                            states[stream.id] = nil
                        }
                    }
                }
            } catch {
                logger.error("backpressure: \(error)")
            }
        }

        func newConnection(
            _ listener: QuicListener, connection: QuicConnection, info: ConnectionInfo
        ) -> QuicStatus {
            events.write { events in
                events.append(.newConnection(listener: listener, connection: connection, info: info))
            }

            return .code(.success)
        }

        func shouldOpen(_: QuicConnection, certificate: Data?) -> QuicStatus {
            guard let certificate else {
                return .code(.requiredCert)
            }
            do {
                let (publicKey, alternativeName) = try parseCertificate(data: certificate, type: .x509)
                if alternativeName != generateSubjectAlternativeName(pubkey: publicKey) {
                    return .code(.badCert)
                }
            } catch {
                return .code(.badCert)
            }
            return .code(.success)
        }

        func connected(_ connection: QuicConnection) {
            events.write { events in
                events.append(.connected(connection: connection))
            }
        }

        func shutdownInitiated(_ connection: QuicConnection, reason: ConnectionCloseReason) {
            events.write { events in
                events.append(.shutdownInitiated(connection: connection, reason: reason))
            }
        }

        func streamStarted(_ connect: QuicConnection, stream: QuicStream) {
            events.write { events in
                events.append(.streamStarted(connection: connect, stream: stream))
            }
        }

        func dataReceived(stream: QuicStream, data: Data?) {
            if isBackpressureEnabled {
                backpressure(data!, on: stream)
                return
            }
            events.write { events in
                events.append(.dataReceived(stream: stream, data: data))
            }
        }

        func closed(_ stream: QuicStream, status: QuicStatus, code: QuicErrorCode) {
            events.write { events in
                events.append(.closed(stream: stream, status: status, code: code))
            }
        }
    }

    let registration: QuicRegistration
    let certData: Data
    let badCertData: Data

    init() throws {
        registration = try QuicRegistration()
        let privateKey = try Ed25519.SecretKey(from: Data32.random())
        certData = try generateSelfSignedCertificate(privateKey: privateKey)
        // Msquic certificate verification passed, custom verification failed
        badCertData = Data(
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
    }

    @Test
    func backpressureRetriesWithinLimit() async throws {
        let serverHandler = MockPeerEventHandler(true)
        let clientHandler = MockPeerEventHandler(true)
        let privateKey1 = try Ed25519.SecretKey(from: Data32.random())
        let cert = try generateSelfSignedCertificate(privateKey: privateKey1)
        let serverConfiguration = try QuicConfiguration(
            registration: registration,
            pkcs12: certData,
            alpns: [Data("testalpn".utf8)],
            client: false,
            settings: QuicSettings.defaultSettings
        )

        let listener = try QuicListener(
            handler: serverHandler,
            registration: registration,
            configuration: serverConfiguration,
            listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 0)!,
            alpns: [Data("testalpn".utf8)]
        )

        let listenAddress = try listener.listenAddress()
        // Client setup with certificate
        let clientConfiguration = try QuicConfiguration(
            registration: registration,
            pkcs12: cert,
            alpns: [Data("testalpn".utf8)],
            client: true,
            settings: QuicSettings.defaultSettings
        )

        let clientConnection = try QuicConnection(
            handler: clientHandler,
            registration: registration,
            configuration: clientConfiguration
        )
        // Attempt to connect
        try clientConnection.connect(to: listenAddress)
        let stream1 = try clientConnection.createStream()
        try stream1.send(data: Data("test data 1".utf8))

        try await Task.sleep(for: .milliseconds(100))
        let (_, info) = serverHandler.events.value.compactMap {
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
    }

    @Test
    func rejectsConDueToBadServerCert() async throws {
        let serverHandler = MockPeerEventHandler()
        let clientHandler = MockPeerEventHandler()

        // Server setup with bad certificate
        let serverConfiguration = try QuicConfiguration(
            registration: registration,
            pkcs12: badCertData,
            alpns: [Data("testalpn".utf8)],
            client: false,
            settings: QuicSettings.defaultSettings
        )

        let listener = try QuicListener(
            handler: serverHandler,
            registration: registration,
            configuration: serverConfiguration,
            listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 0)!,
            alpns: [Data("testalpn".utf8)]
        )

        let listenAddress = try listener.listenAddress()

        // Client setup
        let clientConfiguration = try QuicConfiguration(
            registration: registration,
            pkcs12: certData,
            alpns: [Data("testalpn".utf8)],
            client: true,
            settings: QuicSettings.defaultSettings
        )

        let clientConnection = try QuicConnection(
            handler: clientHandler,
            registration: registration,
            configuration: clientConfiguration
        )

        try clientConnection.connect(to: listenAddress)
        try await Task.sleep(for: .milliseconds(100))
        let (_, reason) = clientHandler.events.value.compactMap {
            switch $0 {
            case let .shutdownInitiated(connection, reason):
                (connection, reason) as (QuicConnection, ConnectionCloseReason)?
            default:
                nil
            }
        }.first!
        #expect(
            reason
                == ConnectionCloseReason.transport(
                    status: QuicStatus.code(QuicStatusCode.badCert), code: QuicErrorCode(298)
                )
        )
    }

    @Test
    func connected() async throws {
        let serverHandler = MockPeerEventHandler()
        let clientHandler = MockPeerEventHandler()
        let privateKey1 = try Ed25519.SecretKey(from: Data32.random())
        let cert = try generateSelfSignedCertificate(privateKey: privateKey1)
        let serverConfiguration = try QuicConfiguration(
            registration: registration,
            pkcs12: certData,
            alpns: [Data("testalpn".utf8)],
            client: false,
            settings: QuicSettings.defaultSettings
        )

        let listener = try QuicListener(
            handler: serverHandler,
            registration: registration,
            configuration: serverConfiguration,
            listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 0)!,
            alpns: [Data("testalpn".utf8)]
        )

        let listenAddress = try listener.listenAddress()
        // Client setup with certificate
        let clientConfiguration = try QuicConfiguration(
            registration: registration,
            pkcs12: cert,
            alpns: [Data("testalpn".utf8)],
            client: true,
            settings: QuicSettings.defaultSettings
        )

        let clientConnection = try QuicConnection(
            handler: clientHandler,
            registration: registration,
            configuration: clientConfiguration
        )

        // Attempt to connect
        try clientConnection.connect(to: listenAddress)
        let stream1 = try clientConnection.createStream()
        try stream1.send(data: Data("test data 1".utf8))

        try await Task.sleep(for: .milliseconds(100))
        let (_, info) = serverHandler.events.value.compactMap {
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
    }

    @Test
    func rejectsConDueToBadClientCert() async throws {
        let serverHandler = MockPeerEventHandler()
        let clientHandler = MockPeerEventHandler()

        let serverConfiguration = try QuicConfiguration(
            registration: registration,
            pkcs12: certData,
            alpns: [Data("testalpn".utf8)],
            client: false,
            settings: QuicSettings.defaultSettings
        )

        let listener = try QuicListener(
            handler: serverHandler,
            registration: registration,
            configuration: serverConfiguration,
            listenAddress: NetAddr(ipAddress: "127.0.0.1", port: 0)!,
            alpns: [Data("testalpn".utf8)]
        )

        let listenAddress = try listener.listenAddress()

        // Client setup with bad certificate
        let clientConfiguration = try QuicConfiguration(
            registration: registration,
            pkcs12: badCertData,
            alpns: [Data("testalpn".utf8)],
            client: true,
            settings: QuicSettings.defaultSettings
        )

        let clientConnection = try QuicConnection(
            handler: clientHandler,
            registration: registration,
            configuration: clientConfiguration
        )
        try clientConnection.connect(to: listenAddress)
        try await Task.sleep(for: .milliseconds(100))
        let (_, reason) = clientHandler.events.value.compactMap {
            switch $0 {
            case let .shutdownInitiated(connection, reason):
                (connection, reason) as (QuicConnection, ConnectionCloseReason)?
            default:
                nil
            }
        }.first!
        #expect(
            reason
                == ConnectionCloseReason.transport(
                    status: QuicStatus.code(QuicStatusCode.badCert), code: QuicErrorCode(298)
                )
        )
    }

    @Test
    func rejectsConDueToWrongCert() async throws {
        // Client setup with wrong certificate
        #expect(
            throws: QuicError.invalidStatus(
                message: "ConfigurationLoadCredential",
                status: QuicStatus(rawValue: QuicStatusCode.tlsError.rawValue)
            )
        ) {
            try QuicConfiguration(
                registration: registration,
                pkcs12: Data("wrong cert data".utf8),
                alpns: [Data("testalpn".utf8)],
                client: false,
                settings: QuicSettings.defaultSettings
            )
        }
    }
}
