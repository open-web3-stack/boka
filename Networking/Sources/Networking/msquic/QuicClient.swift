import Foundation
import msquic

public class QuicClient {
    private let api: UnsafePointer<QuicApiTable>
    private var registration: HQuic?
    private var configuration: HQuic?
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

        api = boundPointer

        var registrationHandle: HQuic?
        let registrationStatus =
            api.pointee.RegistrationOpen(nil, &registrationHandle)
        if QuicStatus(registrationStatus).isFailed {
            throw QuicError.invalidStatus(status: registrationStatus.code)
        }
        registration = registrationHandle
    }

    func start(target: String, port: UInt16) throws {
        try loadConfiguration()
        let connection = try QuicConnection(api: api, registration: registration, configuration: configuration)
        try connection.open()
        try connection.start(target: target, port: port)
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
            api.pointee.ConfigurationClose(configuration)
        }
        if registration != nil {
            api.pointee.RegistrationClose(registration)
        }
        MsQuicClose(api)
    }
}

extension QuicClient {
    private func loadConfiguration(_ unsecure: Bool = true) throws {
        var settings = QUIC_SETTINGS()
        settings.IdleTimeoutMs = 1000
        settings.IsSet.IdleTimeoutMs = 1

//        QUIC_CREDENTIAL_CONFIG CfgConfig = {0};
//        CfgConfig.Flags = QUIC_CREDENTIAL_FLAG_CLIENT | QUIC_CREDENTIAL_FLAG_NO_CERTIFICATE_VALIDATION;
        var credConfig = QUIC_CREDENTIAL_CONFIG()
//        memset(&credConfig, 0, MemoryLayout.size(ofValue: credConfig))
        credConfig.Type = QUIC_CREDENTIAL_TYPE_NONE
        credConfig.Flags = QUIC_CREDENTIAL_FLAG_CLIENT
        if unsecure {
//            credConfig.Flags = QUIC_CREDENTIAL_FLAG_CLIENT.rawValue | QUIC_CREDENTIAL_FLAG_NO_CERTIFICATE_VALIDATION.rawValue
            credConfig
                .Flags =
                QUIC_CREDENTIAL_FLAGS(UInt32(QUIC_CREDENTIAL_FLAG_CLIENT.rawValue | QUIC_CREDENTIAL_FLAG_NO_CERTIFICATE_VALIDATION
                        .rawValue))
        }

        let buffer = Data("sample".utf8)
        let bufferPointer = UnsafeMutablePointer<UInt8>.allocate(
            capacity: buffer.count
        )
        buffer.copyBytes(to: bufferPointer, count: buffer.count)

        var Alpn = QuicBuffer(Length: UInt32(buffer.count), Buffer: bufferPointer)

//        let status = api.pointee.ConfigurationOpen(
//            registration, &Alpn, 1, &settings, UInt32(MemoryLayout.size(ofValue: settings)), nil,
//            &configuration)
        let status = api.pointee.ConfigurationOpen(
            registration, &Alpn, 1, nil, 0, nil,
            &configuration
        )
//        free(bufferPointer)
        if QuicStatus(status).isFailed {
            throw QuicError.invalidStatus(status: status.code)
        }

        let configStatus = api.pointee.ConfigurationLoadCredential(configuration, &credConfig)
        if QuicStatus(configStatus).isFailed {
            throw QuicError.invalidStatus(status: configStatus.code)
        }
    }
}
