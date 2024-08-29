import Foundation
import msquic

struct QuicApi {
    private public let api: UnsafePointer<QuicApiTable>
    private public let registration: HQuic

    init() throws {
        var rawPointer: UnsafeRawPointer?
        let status = MsQuicOpenVersion(2, &rawPointer)

        if QuicStatus(status).isFailed {
            throw QuicError.invalidStatus(status: status.statusCode)
        }

        guard let boundPointer = rawPointer?.assumingMemoryBound(to: QUIC_API_TABLE.self) else {
            throw QuicError.getApiFailed
        }

        api = boundPointer

        var registrationHandle: HQuic?
        let registrationStatus = api.pointee.RegistrationOpen(nil, &registrationHandle)

        if QuicStatus(registrationStatus).isFailed {
            MsQuicClose(api)
            throw QuicError.invalidStatus(status: registrationStatus.statusCode)
        }

        guard let regHandle = registrationHandle else {
            MsQuicClose(api)
            throw QuicError.getRegistrationFailed
        }

        registration = regHandle
    }

    mutating func release() {
        api.pointee.RegistrationClose(registration)
        MsQuicClose(api)
    }
}
