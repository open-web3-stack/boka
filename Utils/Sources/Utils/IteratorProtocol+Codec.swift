import Foundation

extension IteratorProtocol where Element == UInt8 {
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
        for l in 0 ..< byteLengh {
            guard let byte = next() else {
                return nil
            }
            res = res | UInt64(byte) << (8 * l)
        }
        let mask = UInt8(UInt(1) << (8 - byteLengh) - 1)
        let topBits = firstByte & mask

        return res + UInt64(topBits) << (8 * byteLengh)
    }
}
