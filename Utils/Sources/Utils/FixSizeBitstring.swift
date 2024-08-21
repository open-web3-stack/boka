import Foundation
import ScaleCodec

// TODO: add tests
public struct FixSizeBitstring<T: ReadInt>: Hashable, Sendable {
    /// Byte storage for bits.
    public private(set) var bytes: Data
    public private(set) var length: Int
    /// Initialize with byte data storage.
    /// - Parameter bytes: Byte storage for bits.
    public init?(config: T.TConfig, bytes: Data) {
        let length = T.read(config: config)
        guard length == bytes.count else {
            return nil
        }
        self.bytes = bytes
        self.length = length
    }

    private func at(unchecked index: Int) -> Bool {
        let byteIndex = index >> 3
        let bitIndex = 7 - index % 8
        return (bytes[byteIndex] & (1 << bitIndex)) != 0
    }

    /// Formats the bitstring in binary digits.
    public var binaryString: String {
        var s = ""
        for i in 0 ..< length {
            s.append(at(unchecked: i) ? "1" : "0")
        }
        return s
    }

    public var description: String { binaryString }
}

extension FixSizeBitstring: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        guard lhs.bytes.count == rhs.bytes.count else {
            return lhs.bytes.count < rhs.bytes.count
        }
        for (l, r) in zip(lhs.bytes, rhs.bytes) where l != r {
            return l < r
        }
        return false
    }
}

extension FixSizeBitstring: Equatable {
    /**
      Checks for equality
     - parameter lhs: bitstring
     - parameter rhs: bitstring
     - returns true if the bitstrings are equal, false otherwise
      */
    public static func == (lhs: FixSizeBitstring, rhs: FixSizeBitstring) -> Bool {
        guard lhs.bytes.count == rhs.bytes.count else {
            return false
        }
        return lhs.bytes == rhs.bytes
    }
}

extension FixSizeBitstring {
    public init<D: ScaleCodec.Decoder>(
        config: T.TConfig,
        from decoder: inout D,
        decodeItem _: @escaping (inout D) throws -> T
    ) throws {
        let length = T.read(config: config)
        try self.init(bytes: decoder.decode(Data.self, .fixed(UInt(length))), length: length)
    }
}

extension FixSizeBitstring where T: ScaleCodec.Decodable {
    public init(config: T.TConfig, from decoder: inout some ScaleCodec.Decoder) throws {
        let length = T.read(config: config)
        try self.init(bytes: decoder.decode(Data.self, .fixed(UInt(length))), length: length)
    }
}
