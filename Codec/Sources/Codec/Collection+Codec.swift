import Foundation

extension Collection<UInt8> where SubSequence == Self {
    public mutating func next() -> UInt8? {
        guard let byte = first else {
            return nil
        }
        self = dropFirst()
        return byte
    }

    // implements the general natural number serialization format
    public mutating func decode() -> UInt64? {
        guard let firstByte = next() else {
            return nil
        }
        if firstByte == 0 {
            return 0
        }
        let byteLengh = (~firstByte).leadingZeroBitCount
        var res: UInt64 = 0
        if byteLengh > 0 {
            guard let rest: UInt64 = decode(length: byteLengh) else {
                return nil
            }
            res = rest
        }

        let mask = UInt8(UInt(1) << (8 - byteLengh) - 1)
        let topBits = firstByte & mask

        return res + UInt64(topBits) << (8 * byteLengh)
    }

    // TODO: this is pretty inefficient
    // so need to ensure the usage of this is minimal
    public mutating func decode<T: UnsignedInteger>(length: Int) -> T? {
        guard length > 0 else {
            return nil
        }
        var res: T = 0
        for l in 0 ..< length {
            guard let byte = next() else {
                return nil
            }
            res = res | T(byte) << (8 * l)
        }
        return res
    }
}
