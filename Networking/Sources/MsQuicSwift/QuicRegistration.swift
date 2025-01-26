import msquic

public final class QuicRegistration: @unchecked Sendable {
    public let api: QuicAPI
    let ptr: HQUIC

    public init(api: QuicAPI = .shared) throws(QuicError) {
        self.api = api
        var ptr: HQUIC?
        try api.call("RegistrationOpen") { api in
            api.pointee.RegistrationOpen(nil, &ptr)
        }
        self.ptr = ptr!
    }

    deinit {
        api.call { api in
            api.pointee.RegistrationClose(ptr)
        }
    }
}
