import Foundation

extension Collection<UInt8> where SubSequence == Self {
    // implements the general natural number serialization format
    public mutating func decodeScale() -> UInt64? {
        ScaleIntegerCodec.decode { self.next() }
    }
}

public enum ScaleIntegerCodec {
    public static func decode(next: () throws -> UInt8?) rethrows -> UInt64? {
        guard let firstByte = try next() else {
            return nil
        }
        if firstByte == 0 {
            return 0
        }

        switch firstByte & 0b11 {
        case 0b00: // 1 byte
            return UInt64(firstByte >> 2)
        case 0b01: // 2 bytes
            guard let secondByte = try next() else {
                return nil
            }
            return UInt64(firstByte >> 2) | (UInt64(secondByte) << 6)
        case 0b10: // 4 bytes
            guard let secondByte = try next() else {
                return nil
            }
            guard let thirdByte = try next() else {
                return nil
            }
            guard let fourthByte = try next() else {
                return nil
            }
            let value = UInt64(firstByte >> 2) | (UInt64(secondByte) << 6) | (UInt64(thirdByte) << 14) | (UInt64(fourthByte) << 22)
            return value
        case 0b11: // variable bytes
            fatalError("variable bytes compact codec not implemented")
        default:
            fatalError("unreachable")
        }
    }
}
