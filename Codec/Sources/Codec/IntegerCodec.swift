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

    // this is pretty inefficient
    // so need to ensure the usage of this is minimal
    public mutating func decode<T: UnsignedInteger>(length: Int) -> T? {
        IntegerCodec.decode(length: length) { self.next() }
    }
}

public enum IntegerCodec {
    public static func decode<T: UnsignedInteger>(length: Int, next: () throws -> UInt8?) rethrows -> T? {
        guard length > 0 else {
            return nil
        }
        var res: T = 0
        for l in 0 ..< length {
            guard let byte = try next() else {
                return nil
            }
            res = res | T(byte) << (8 * l)
        }
        return res
    }

    public static func decode(next: () throws -> UInt8?) rethrows -> UInt64? {
        guard let firstByte = try next() else {
            return nil
        }
        if firstByte == 0 {
            return 0
        }

        let byteLengh = (~firstByte).leadingZeroBitCount
        var res: UInt64 = 0
        if byteLengh > 0 {
            guard let rest: UInt64 = try decode(length: byteLengh, next: next) else {
                return nil
            }
            res = rest
        }

        let mask = UInt8(UInt(1) << (8 - byteLengh) - 1)
        let topBits = firstByte & mask

        return res + UInt64(topBits) << (8 * byteLengh)
    }
}
