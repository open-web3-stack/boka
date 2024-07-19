import Foundation

extension Collection<UInt8> where SubSequence == Self {
    public mutating func next() -> UInt8? {
        guard let byte = self[safe: startIndex] else {
            return nil
        }
        let nextIndex = index(after: startIndex)
        self = self[nextIndex ..< endIndex]
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
            guard let rest = decode(length: byteLengh) else {
                return nil
            }
            res = rest
        }

        let mask = UInt8(UInt(1) << (8 - byteLengh) - 1)
        let topBits = firstByte & mask

        return res + UInt64(topBits) << (8 * byteLengh)
    }

    public mutating func decode(length: Int) -> UInt64? {
        guard length > 0 else {
            return nil
        }
        var res: UInt64 = 0
        for l in 0 ..< length {
            guard let byte = next() else {
                return nil
            }
            res = res | UInt64(byte) << (8 * l)
        }
        return res
    }
}
