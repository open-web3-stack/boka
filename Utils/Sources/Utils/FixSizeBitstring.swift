import Foundation

public enum ConfigBitstringError: Swift.Error {
    case missingConfig
    case notEnoughData
}

// TODO: add tests
public struct FixSizeBitstring<TByteLength: ReadInt>: Hashable, Sendable {
    /// Byte storage for bits.
    public private(set) var bytes: Data
    /// length of the bitstring
    public private(set) var length: Int
    /// Initialize with byte data storage and length.
    /// - Parameter bytes: Byte storage for bits.
    public init(bytes: Data, length: Int) throws(ConfigBitstringError) {
        guard bytes.count * 8 >= length else {
            throw ConfigBitstringError.notEnoughData
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
        lhs.length == rhs.length && lhs.bytes == rhs.bytes
    }
}

extension FixSizeBitstring: Decodable {
    public init(from decoder: any Decoder) throws {
        guard let config = decoder.getConfig(TByteLength.TConfig.self) else {
            throw ConfigBitstringError.missingConfig
        }
        let length = TByteLength.read(config: config)
        var container = try decoder.unkeyedContainer()
        let bytes = try container.decode(Data.self)
        try self.init(bytes: bytes, length: length)
    }
}

extension FixSizeBitstring: Encodable {
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(length)
        try container.encode(bytes)
    }
}
