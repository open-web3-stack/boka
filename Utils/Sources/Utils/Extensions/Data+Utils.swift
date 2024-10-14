import Foundation

extension Data {
    public init?(fromHexString hexString: String) {
        guard !hexString.isEmpty else {
            self.init()
            return
        }

        var data = Data()
        var index = hexString.startIndex

        while index < hexString.endIndex {
            guard
                let nextIndex = hexString.index(index, offsetBy: 2, limitedBy: hexString.endIndex),
                let byte = UInt8(hexString[index ..< nextIndex], radix: 16)
            else {
                return nil
            }

            data.append(byte)
            index = nextIndex
        }

        self.init(data)
    }

    public func toHexString() -> String {
        map { String(format: "%02x", $0) }.joined()
    }

    public func toDebugHexString() -> String {
        if count > 32 {
            let prefix = prefix(8).map { String(format: "%02x", $0) }.joined()
            let suffix = suffix(8).map { String(format: "%02x", $0) }.joined()
            return "0x\(prefix)...\(suffix) (\(count) bytes)"
        } else {
            return "0x\(map { String(format: "%02x", $0) }.joined())"
        }
    }

    public func decode<T: FixedWidthInteger>(_: T.Type) -> T {
        assert(MemoryLayout<T>.size <= count)
        return withUnsafeBytes { ptr in
            ptr.loadUnaligned(as: T.self)
        }
    }
}

extension FixedSizeData {
    public init?(fromHexString hexString: String) {
        guard let data = Data(fromHexString: hexString) else {
            return nil
        }
        self.init(data)
    }

    public func toHexString() -> String {
        data.toHexString()
    }
}

extension [Data] {
    public func withContentUnsafeBytes<R>(_ fn: ([UnsafeRawBufferPointer]) throws -> R) rethrows -> R {
        func helper(data: ArraySlice<Data>, ptr: [UnsafeRawBufferPointer]) throws -> R {
            if data.isEmpty {
                return try fn(ptr)
            }
            let rest = data.dropFirst()
            let first = data.first!
            return try first.withUnsafeBytes { (bufferPtr: UnsafeRawBufferPointer) -> R in
                return try helper(data: rest, ptr: ptr + [bufferPtr])
            }
        }

        return try helper(data: self[...], ptr: [])
    }
}
