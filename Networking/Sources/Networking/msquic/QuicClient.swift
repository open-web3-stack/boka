import Foundation
import msquic

public class QuicClient {
    private var api: UnsafePointer<QuicApiTable>?
    private var registration: HQuic?
    private var configuration: HQuic?
    private var connection: QuicConnection?
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
    }

    func start(target: String, port: UInt16) throws {
        try loadConfiguration()
        connection = try QuicConnection(
            api: api, registration: registration, configuration: configuration
        )
        try connection?.open()
        try connection?.start(target: target, port: port)
        print("Connection started")
    }

    func connect() throws -> QuicStatus {
        QuicStatusCode.success.rawValue
    }

    func send(message _: Data) throws -> QuicStatus {
        QuicStatusCode.success.rawValue
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
//        api = nil
        print("QuicClient Deinit")
    }
}

extension QuicClient {
    private func loadConfiguration(_ unsecure: Bool = true) throws {
        var settings = QUIC_SETTINGS()
        settings.IdleTimeoutMs = 1000
        settings.IsSet.IdleTimeoutMs = 1

        //        CfgConfig.Flags = QUIC_CREDENTIAL_FLAG_CLIENT | QUIC_CREDENTIAL_FLAG_NO_CERTIFICATE_VALIDATION;
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

        var alpn = QuicBuffer(Length: UInt32(buffer.count), Buffer: bufferPointer)

        //        let status = api.pointee.ConfigurationOpen(
        //            registration, &Alpn, 1, &settings, UInt32(MemoryLayout.size(ofValue: settings)), nil,
        //            &configuration)
        let status =
            (api?.pointee.ConfigurationOpen(
                registration, &alpn, 1, nil, 0, nil,
                &configuration
            )).status
        free(bufferPointer)
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
