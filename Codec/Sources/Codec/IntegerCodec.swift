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
    public enum DecodeMode {
        case jam
        case scale
    }

    // TODO: remove scale codec after JAM test vectors are updated
    public nonisolated(unsafe) static var decodeMode: DecodeMode = .jam

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

        if decodeMode == .scale {
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
