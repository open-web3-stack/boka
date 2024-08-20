import Foundation
import ScaleCodec

public struct Bitstring: Hashable, Sendable {
    /// Total number of bits.
    public private(set) var length: Int
    /// Byte storage for bits.
    public private(set) var bytes: Data

    /// Initialize with total bit length and byte storage.
    ///
    /// - Parameters:
    ///   - length: Total number of bits.
    ///   - bytes: Byte storage for bits.
    ///
    private init(length: Int, bytes: Data) {
        self.bytes = bytes
        self.length = length
    }

    /// Initialize with byte data storage.
    ///
    /// The total bit count of the bit string is assumed to be
    /// all the bits the provided in the `bytes` parameter.
    ///
    /// - Parameter bytes: Byte storage for bits.
    ///
    public init(bytes: Data) {
        self.bytes = bytes
        length = bytes.count * 8
    }

    public init(length: Int) {
        self.length = length
        let byteCount = (length + 7) / 8
        bytes = Data(repeating: 0, count: byteCount)
    }

    /// Initialize with binaryString.
    ///
    /// - Parameter bitString: String of bit array. Each character of the string must be a `1` or `0`.
    /// - Returns: Initialized ``BitString`` or `nil` if any character of the string is not a `1` or `0`.
    ///
    public init?(_ binaryString: String) {
        // Ensure the string only contains '0' and '1'
        guard binaryString.allSatisfy({ $0 == "0" || $0 == "1" }) else {
            return nil
        }
        let length = binaryString.count
        var bytes = Data(repeating: 0, count: (length + 7) / 8) // +7 to round up to the nearest byte
        for (index, char) in binaryString.enumerated() where char == "1" {
            let byteIndex = index >> 3
            let bitIndex = 7 - (index % 8)
            bytes[byteIndex] |= (1 << bitIndex)
        }
        self.init(length: length, bytes: bytes)
    }

    private func at(unchecked index: Int) -> Int {
        let byteIndex = index >> 3
        let bitIndex = 7 - index % 8
        return (bytes[byteIndex] & (1 << bitIndex)) != 0 ? 1 : 0
    }

    /// String of bit array as text representation with each character a `0` or `1`.
    public var bitString: String {
        bytes.map { ($0 != 0) ? "1" : "0" }.joined(separator: "")
    }

    /// Formats the bitstring in binary digits.
    public var binaryString: String {
        var s = ""
        for i in 0 ..< length {
            s.append(at(unchecked: i) == 1 ? "1" : "0")
        }
        return s
    }

    /// Formats as bit squences
    public var bitSquences: [Bool] {
        binaryString.map { $0 == "1" }
    }

    public var description: String { binaryString }
}

extension Bitstring: Comparable {
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

extension Bitstring: Equatable {
    /**
      Checks for equality
     - parameter lhs: bitstring
     - parameter rhs: bitstring
     - returns true if the bitstrings are equal, false otherwise
      */
    public static func == (lhs: Bitstring, rhs: Bitstring) -> Bool {
        guard lhs.bytes.count == rhs.bytes.count else {
            return false
        }
        return lhs.bytes == rhs.bytes
    }
}

extension Bitstring: ScaleCodec.Codable {
    public init(from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(bytes: decoder.decode(Data.self))
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(bytes)
    }
}
