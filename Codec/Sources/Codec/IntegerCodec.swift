import Foundation

extension Collection<UInt8> where SubSequence == Self {
    public mutating func next() -> UInt8? {
        let byte = first
        self = dropFirst()
        return byte
    }

    // implements the general natural number serialization format
    public mutating func decode() -> UInt64? {
        IntegerCodec.decode { self.next() }
    }

    public mutating func decode<T: UnsignedInteger>(length: Int) -> T? {
        guard length > 0, length <= count else { return nil }

        // fast path for Data
        if let data = self as? Data {
            let result: T? = data.withUnsafeBytes { buffer in
                guard length <= buffer.count else { return nil }
                let ptr = buffer.bindMemory(to: UInt8.self)

                var result: T = 0
                for i in 0 ..< length {
                    let byte = T(ptr[i])
                    result |= byte << (8 * i)
                }
                return result
            }
            self = dropFirst(length)
            return result
        }

        // fallback
        var result: T = 0
        for i in 0 ..< length {
            let index = index(startIndex, offsetBy: i)
            let byte = T(self[index])
            result |= byte << (8 * i)
        }
        self = dropFirst(length)
        return result
    }
}

public enum IntegerCodec {
    public static func decode(next: () throws -> UInt8?) rethrows -> UInt64? {
        guard let firstByte = try next() else {
            return nil
        }
        if firstByte == 0 {
            return 0
        }

        let byteLength = (~firstByte).leadingZeroBitCount
        var res: UInt64 = 0
        if byteLength > 0 {
            for i in 0 ..< byteLength {
                guard let byte = try next() else {
                    return nil
                }
                res |= UInt64(byte) << (8 * i)
            }
        }

        let mask = UInt8(UInt(1) << (8 - byteLength) - 1)
        let topBits = firstByte & mask

        return res + UInt64(topBits) << (8 * byteLength)
    }
}
