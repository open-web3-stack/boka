import Foundation
import Logging
import msquic
import NIO

let clientLogger = Logger(label: "QuicClient")

public protocol QuicClientMessageHandler: AnyObject {
    func didReceiveMessage(quicClient: QuicClient, message: QuicMessage)
    func didReceiveError(quicClient: QuicClient, error: QuicError)
}

public class QuicClient: @unchecked Sendable {
    private let api: UnsafePointer<QuicApiTable>?
    private var registration: HQuic?
    private var configuration: HQuic?
    private var connection: QuicConnection?
    // TODO: remove persistent stream
    // private var persistentStream: QuicStream?
    private let config: QuicConfig
    private weak var messageHandler: QuicClientMessageHandler?

    init(config: QuicConfig, messageHandler: QuicClientMessageHandler? = nil) throws {
        self.config = config
        self.messageHandler = messageHandler
        var rawPointer: UnsafeRawPointer?
        let status: UInt32 = MsQuicOpenVersion(2, &rawPointer)

        if QuicStatus(status).isFailed {
            throw QuicError.invalidStatus(status: status.code)
        }
        guard
            let boundPointer: UnsafePointer<QuicApiTable> = rawPointer?.assumingMemoryBound(
                to: QuicApiTable.self
            )
        else {
            throw QuicError.getApiFailed
        }

        var registrationHandle: HQuic?
        let registrationStatus =
            boundPointer.pointee.RegistrationOpen(nil, &registrationHandle)
        if QuicStatus(registrationStatus).isFailed {
            throw QuicError.invalidStatus(status: registrationStatus.code)
        }

        api = boundPointer
        registration = registrationHandle
    }

    func start() throws -> QuicStatus {
        let status = QuicStatusCode.success.rawValue
        try loadConfiguration()
        connection = QuicConnection(
            api: api, registration: registration, configuration: configuration, messageHandler: self
        )
        try connection?.open()
        try connection?.start(ipAddress: config.ipAddress, port: config.port)
        return status
    }

    // Asynchronous send method that waits for a reply
    func send(message: Data) async throws -> QuicMessage {
        try await send(message: message, streamKind: .uniquePersistent)
    }

    // Asynchronous send method that waits for a reply
    func send(message: Data, streamKind: StreamKind = .uniquePersistent) async throws -> QuicMessage {
        guard let connection else {
            throw QuicError.getConnectionFailed
        }
        let sendStream: QuicStream
        // Check if there is an existing stream of the same kind
        if streamKind == .uniquePersistent {
            // If there is, send the message to the existing stream
            sendStream = try connection.createOrGetUniquePersistentStream(kind: streamKind)
        } else {
            // If there is not, create a new stream
            sendStream = try connection.createCommonEphemeralStream()
            // Start the stream
            try sendStream.start()
        }
        return try await sendStream.send(buffer: message)
    }

    func getNetAddr() -> NetAddr {
        NetAddr(ipAddress: config.ipAddress, port: config.port)
    }

    func close() {
        if let connection {
            connection.close()
            self.connection = nil
        }

        if let configuration {
            api?.pointee.ConfigurationClose(configuration)
            self.configuration = nil
        }

        if let registration {
            api?.pointee.RegistrationClose(registration)
            self.registration = nil
        }

        MsQuicClose(api)

        if let messageHandler {
            messageHandler.didReceiveMessage(quicClient: self, message: QuicMessage(type: .close, data: nil))
        }
    }

    deinit {
        clientLogger.info("QuicClient Deinit")
    }
}

extension QuicClient: QuicConnectionMessageHandler {
    public func didReceiveMessage(
        connection _: QuicConnection, stream _: QuicStream?, message: QuicMessage
    ) {
        switch message.type {
        case .received:
            let buffer = message.data!
            clientLogger.info(
                "Client received: \(String([UInt8](buffer).map { Character(UnicodeScalar($0)) }))"
            )

        case .shutdownComplete:
            // Use [weak self] to avoid strong reference cycle
            DispatchQueue.main.async { [weak self] in
                self?.close()
            }

        default:
            break
        }
    }

    public func didReceiveError(
        connection _: QuicConnection, stream _: QuicStream, error: QuicError
    ) {
        clientLogger.error("Failed to receive message: \(error)")
    }
}

extension QuicClient {
    private func loadConfiguration(_ unsecure: Bool = false) throws {
        var settings = QUIC_SETTINGS()
        settings.IdleTimeoutMs = 10000
        settings.IsSet.IdleTimeoutMs = 1

        var certificateFile = QUIC_CERTIFICATE_FILE()
        var credConfig = QUIC_CREDENTIAL_CONFIG()

        credConfig.Flags = QUIC_CREDENTIAL_FLAG_CLIENT
        if unsecure {
            credConfig.Flags = QUIC_CREDENTIAL_FLAGS(
                UInt32(
                    QUIC_CREDENTIAL_FLAG_CLIENT.rawValue
                        | QUIC_CREDENTIAL_FLAG_NO_CERTIFICATE_VALIDATION.rawValue
                )
            )
        } else {
            let certCString = config.cert.utf8CString
            let keyFileCString = config.key.utf8CString

            let certPointer = UnsafeMutablePointer<CChar>.allocate(capacity: certCString.count)
            let keyFilePointer = UnsafeMutablePointer<CChar>.allocate(capacity: keyFileCString.count)
            // Copy the C strings to the pointers
            certCString.withUnsafeBytes {
                certPointer.initialize(
                    from: $0.bindMemory(to: CChar.self).baseAddress!, count: certCString.count
                )
            }

            keyFileCString.withUnsafeBytes {
                keyFilePointer.initialize(
                    from: $0.bindMemory(to: CChar.self).baseAddress!, count: keyFileCString.count
                )
            }

            certificateFile.CertificateFile = UnsafePointer(certPointer)
            certificateFile.PrivateKeyFile = UnsafePointer(keyFilePointer)
            let certificateFilePointer =
                UnsafeMutablePointer<QUIC_CERTIFICATE_FILE>.allocate(capacity: 1)
            certificateFilePointer.initialize(to: certificateFile)
            credConfig.Type = QUIC_CREDENTIAL_TYPE_CERTIFICATE_FILE
            credConfig.Flags = QUIC_CREDENTIAL_FLAG_NONE
            credConfig.CertificateFile = certificateFilePointer
        }

        let buffer = Data(config.alpn.utf8)
        let bufferPointer = UnsafeMutablePointer<UInt8>.allocate(
            capacity: buffer.count
        )
        buffer.copyBytes(to: bufferPointer, count: buffer.count)
        defer {
            free(bufferPointer)
        }
        var alpn = QuicBuffer(Length: UInt32(buffer.count), Buffer: bufferPointer)

        let status =
            (api?.pointee.ConfigurationOpen(
                registration, &alpn, 1, &settings, UInt32(MemoryLayout.size(ofValue: settings)),
                nil,
                &configuration
            )).status

        if status.isFailed {
            throw QuicError.invalidStatus(status: status.code)
        }

        let configStatus = (api?.pointee.ConfigurationLoadCredential(configuration, &credConfig))
            .status
        if configStatus.isFailed {
            throw QuicError.invalidStatus(status: configStatus.code)
        }
    }
}
