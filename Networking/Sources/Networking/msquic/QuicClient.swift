import Foundation
import msquic
import NIO

public class QuicClient {
    private var api: UnsafePointer<QuicApiTable>?
    private var registration: HQuic?
    private var configuration: HQuic?
    private var connection: QuicConnection?
    public var onMessageReceived: ((Result<QuicMessage, QuicError>) -> Void)?
    private let config: QuicConfig

    init(config: QuicConfig) throws {
        self.config = config
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
        connection = try QuicConnection(
            api: api, registration: registration, configuration: configuration
        )
        try connection?.open()
        try connection?.start(ipAddress: config.ipAddress, port: config.port)
        connection?.onMessageReceived = { [weak self] message in
            guard let self else { return }
            onMessageReceived?(message)
        }
        return status
    }

    func connect() throws -> QuicStatus {
        QuicStatusCode.success.rawValue
    }

    // TODO: check stream & send
    func send(message: Data) throws {
        try send(message: message, streamKind: .uniquePersistent)
    }

    // TODO: more send methods
    func send(message: Data, streamKind: StreamKind = .commonEphemeral) throws {
        guard let connection else {
            throw QuicError.getConnectionFailed
        }
        // TODO: check stream type & send
        let stream = try connection.createStream(streamKind)
        stream.onMessageReceived = { [weak self] result in
            self?.onMessageReceived?(result)
        }
        try stream.start()
        stream.send(buffer: message)
    }

    deinit {
        if configuration != nil {
            api?.pointee.ConfigurationClose(configuration)
            configuration = nil
        }
        if registration != nil {
            api?.pointee.RegistrationClose(registration)
            registration = nil
        }
        MsQuicClose(api)
    }
}

extension QuicClient {
    private func loadConfiguration(_ unsecure: Bool = true) throws {
        var settings = QUIC_SETTINGS()
        settings.IdleTimeoutMs = 30000
        settings.IsSet.IdleTimeoutMs = 1

        var credConfig = QUIC_CREDENTIAL_CONFIG()
        memset(&credConfig, 0, MemoryLayout.size(ofValue: credConfig))
        credConfig.Flags = QUIC_CREDENTIAL_FLAG_CLIENT
        if unsecure {
            credConfig.Flags = QUIC_CREDENTIAL_FLAGS(
                UInt32(
                    QUIC_CREDENTIAL_FLAG_CLIENT.rawValue
                        | QUIC_CREDENTIAL_FLAG_NO_CERTIFICATE_VALIDATION.rawValue
                )
            )
        } else {
            credConfig.Flags = QUIC_CREDENTIAL_FLAG_CLIENT
            //     TODO: load cert and key
            //    credConfig.CertificateFile = UnsafePointer<Int8>(strdup(config.cert))
            //    credConfig.PrivateKeyFile = UnsafePointer<Int8>(strdup(config.key))
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
