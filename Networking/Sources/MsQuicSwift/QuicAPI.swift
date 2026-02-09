import msquic
import Utils

public final class QuicAPI: Sendable {
    private let api: SendablePointer<QUIC_API_TABLE>

    public init() throws(QuicError) {
        var ptr: UnsafeRawPointer?
        try MsQuicOpenVersion(2, &ptr).requireSucceeded("MsQuicOpenVersion")

        api = ptr!.assumingMemoryBound(
            to: QUIC_API_TABLE.self,
        ).asSendable
    }

    deinit {
        MsQuicClose(api.value)
    }

    func call(
        _ message: String,
        fn: (UnsafePointer<QUIC_API_TABLE>) throws(QuicError) -> UInt32,
    ) throws(QuicError) {
        try fn(api.value).requireSucceeded(message)
    }

    func call(
        fn: (UnsafePointer<QUIC_API_TABLE>) -> Void,
    ) {
        fn(api.value)
    }

    public static let shared = try! QuicAPI()
}

extension UInt32 {
    private var asQuicStatus: QuicStatus {
        QuicStatus(rawValue: self)
    }

    fileprivate func requireSucceeded(_ message: String) throws(QuicError) {
        try asQuicStatus.requireSucceeded(message)
    }
}
