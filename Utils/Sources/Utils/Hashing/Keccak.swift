import Blake2
import Foundation
import sha3_iuf

public struct Keccak: /* ~Copyable, */ Hashing {
    private var ctx: sha3_context = .init()

    public init() {
        sha3_Init256(&ctx)
        sha3_SetFlags(&ctx, SHA3_FLAGS_KECCAK)
    }

    public mutating func update(_ data: any DataPtrRepresentable) {
        data.withPtr { ptr in
            sha3_Update(&ctx, ptr.baseAddress, ptr.count)
        }
    }

    public consuming func finalize() -> Data32 {
        let ptr = sha3_Finalize(&ctx)!
        let data = Data(bytes: ptr, count: 32)
        return Data32(data)!
    }
}
