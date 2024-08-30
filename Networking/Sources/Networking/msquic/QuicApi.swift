import Foundation
import msquic

public final class QuicApi {
    public private(set) var api: UnsafePointer<QuicApiTable>
    public private(set) var registration: HQuic

    init() throws {
        var rawPointer: UnsafeRawPointer?
        let status = MsQuicOpenVersion(2, &rawPointer)

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
        let registrationStatus = api.pointee.RegistrationOpen(nil, &registrationHandle)

        if QuicStatus(registrationStatus).isFailed {
            MsQuicClose(api)
            throw QuicError.invalidStatus(status: registrationStatus.code)
        }

        guard let regHandle = registrationHandle else {
            MsQuicClose(api)
            throw QuicError.getRegistrationFailed
        }

        registration = regHandle
    }

    deinit {
        api.pointee.RegistrationClose(registration)
        MsQuicClose(api)
    }
}
