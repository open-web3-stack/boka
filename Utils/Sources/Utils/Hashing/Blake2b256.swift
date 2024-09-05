import Blake2
import Foundation

public struct Blake2b256: /* ~Copyable, */ Hashing {
    private var hasher: Blake2b

    public init() {
        // it can never fail
        hasher = try! Blake2b(size: 32)
    }

    public mutating func update(_ data: any DataPtrRepresentable) {
        hasher.update(data)
    }

    public consuming func finalize() -> Data32 {
        // Not possible to finalize twice thanks to the ~Copyable requirement
        let data = try! hasher.finalize()
        return Data32(data)!
    }
}

extension DataPtrRepresentable {
    public func blake2b256hash() -> Data32 {
        Blake2b256.hash(self)
    }
}
