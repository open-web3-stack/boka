import Foundation
import msquic
import NIO

public final class QuicClient {
    private var api: UnsafePointer<QuicApiTable>?
    private var registration: HQuic?
    private var configuration: HQuic?
    private var connection: QuicConnection?
    private var group: MultiThreadedEventLoopGroup?

    init() throws {
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
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    func start(ipAddress: String, port: UInt16) throws {
        try loadConfiguration()
        connection = try QuicConnection(
            api: api, registration: registration, configuration: configuration
        )
        try connection?.open()
        try connection?.start(ipAddress: ipAddress, port: port)
    }

    func connect() throws -> QuicStatus {
        QuicStatusCode.success.rawValue
    }

    func wait() throws {
        try group?.next().scheduleTask(in: .hours(1)) {}.futureResult.wait()
    }

    func send(message: Data) throws {
        guard let connection else {
            throw QuicError.getConnectionFailed
//            return QuicStatusCode.internalError.rawValue
        }
        connection.clientSend(message: message)
    }

    deinit {
        print("QuicClient Deinit")

        if configuration != nil {
            api?.pointee.ConfigurationClose(configuration)
            configuration = nil
        }
        if registration != nil {
            api?.pointee.RegistrationClose(registration)
            registration = nil
        }
        MsQuicClose(api)
        try? group?.syncShutdownGracefully()
    }
}

extension QuicClient {
    private func loadConfiguration(_ unsecure: Bool = true) throws {
        var settings = QUIC_SETTINGS()
        settings.IdleTimeoutMs = 30000
        settings.IsSet.IdleTimeoutMs = 1

        var credConfig = QUIC_CREDENTIAL_CONFIG()
        memset(&credConfig, 0, MemoryLayout.size(ofValue: credConfig))
        //        credConfig.Type = QUIC_CREDENTIAL_TYPE_NONE
        credConfig.Flags = QUIC_CREDENTIAL_FLAG_CLIENT
        if unsecure {
            //            credConfig.Flags = QUIC_CREDENTIAL_FLAG_CLIENT.rawValue | QUIC_CREDENTIAL_FLAG_NO_CERTIFICATE_VALIDATION.rawValue
            credConfig
                .Flags =
                QUIC_CREDENTIAL_FLAGS(
                    UInt32(
                        QUIC_CREDENTIAL_FLAG_CLIENT.rawValue
                            | QUIC_CREDENTIAL_FLAG_NO_CERTIFICATE_VALIDATION
                            .rawValue
                    )
                )
        }

        let buffer = Data("sample".utf8)
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
        //        let status =
        //            (api?.pointee.ConfigurationOpen(
        //                registration, &alpn, 1, nil, 0, nil,
        //                &configuration
        //            )).status

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
