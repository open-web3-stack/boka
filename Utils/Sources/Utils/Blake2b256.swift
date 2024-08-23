import Blake2
import Foundation

public struct Blake2b256: ~Copyable {
    private var hasher: Blake2b

    public init() {
        // it can never fail
        hasher = try! Blake2b(size: 32)
    }

    public mutating func update(_ data: some DataPtrRepresentable) {
        hasher.update(data)
    }

    public consuming func finalize() -> Data32 {
        // Not possible to finalize twice thanks to the ~Copyable requirement
        let data = try! hasher.finalize()
        return Data32(data)!
    }
}

extension Data {
    public func blake2b256hash() -> Data32 {
        var hasher = Blake2b256()
        hasher.update(self)
        return hasher.finalize()
    }
}

extension FixedSizeData {
    public func blake2b256hash() -> Data32 {
        var hasher = Blake2b256()
        hasher.update(data)
        return hasher.finalize()
    }
}
