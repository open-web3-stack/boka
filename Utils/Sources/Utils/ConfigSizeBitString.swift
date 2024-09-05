import Codec
import Foundation

public enum ConfigSizeBitStringError: Error {
    case missingConfig
    case invalidData
    case invalidIndex
}

public struct ConfigSizeBitString<TBitLength: ReadInt>: Equatable, Sendable, Codable {
    /// Byte storage for bits.
    private var bytes: Data
    /// Bit length
    public let length: Int

    private var byteLength: Int {
        (length + 7) / 8
    }

    public init(config: TBitLength.TConfig, data: Data) throws(ConfigSizeBitStringError) {
        length = TBitLength.read(config: config)
        bytes = data

        if byteLength != data.count {
            throw .invalidData
        }
    }

    public init(config: TBitLength.TConfig) {
        length = TBitLength.read(config: config)
        let byteLength = (length + 7) / 8
        bytes = Data(repeating: 0, count: byteLength)
    }

    private func at(unchecked index: Int) -> Bool {
        let byteIndex = index / 8
        let bitIndex = index % 8
        return (bytes[byteIndex] & (1 << bitIndex)) != 0
    }

    /// Formats the bitstring in binary digits.
    public var binaryString: String {
        (0 ..< length).map { at(unchecked: $0) ? "1" : "0" }.joined()
    }

    public var description: String { binaryString }

    public func at(_ index: Int) throws(ConfigSizeBitStringError) -> Bool {
        guard index < length else {
            throw .invalidIndex
        }
        return at(unchecked: index)
    }

    public mutating func set(_ index: Int, to value: Bool) throws(ConfigSizeBitStringError) {
        guard index < length else {
            throw .invalidIndex
        }
        let byteIndex = index / 8
        let bitIndex = index % 8
        if value {
            bytes[byteIndex] |= (1 << bitIndex)
        } else {
            bytes[byteIndex] &= ~(1 << bitIndex)
        }
    }
}

extension ConfigSizeBitString: RandomAccessCollection {
    public typealias Element = Bool

    public var startIndex: Int {
        0
    }

    public var endIndex: Int {
        length
    }

    public subscript(position: Int) -> Bool {
        get {
            try! at(position)
        }
        set {
            try! set(position, to: newValue)
        }
    }

    public func index(after i: Int) -> Int {
        i + 1
    }

    public func index(before i: Int) -> Int {
        i - 1
    }

    public func index(_ i: Int, offsetBy distance: Int) -> Int {
        i + distance
    }

    public func index(_ i: Int, offsetBy distance: Int, limitedBy limit: Int) -> Int? {
        i + distance < limit ? i + distance : nil
    }

    public func distance(from start: Int, to end: Int) -> Int {
        end - start
    }

    public func formIndex(after i: inout Int) {
        i += 1
    }

    public func formIndex(before i: inout Int) {
        i -= 1
    }
}

extension ConfigSizeBitString: FixedLengthData {
    public var data: Data { bytes }

    public static func length(decoder: Decoder) throws -> Int {
        guard let config = decoder.getConfig(TBitLength.TConfig.self) else {
            throw ConfigSizeBitStringError.missingConfig
        }
        return (TBitLength.read(config: config) + 7) / 8
    }

    public init(decoder: Decoder, data: Data) throws {
        guard let config = decoder.getConfig(TBitLength.TConfig.self) else {
            throw ConfigSizeBitStringError.missingConfig
        }
        try self.init(config: config, data: data)
    }
}

extension ConfigSizeBitString: EncodedSize {
    public var encodedSize: Int {
        bytes.count
    }

    public static var encodeedSizeHint: Int? {
        nil
    }
}

extension ConfigSizeBitString: DataPtrRepresentable {
    public func withPtr<R>(
        cb: (UnsafeRawBufferPointer) throws -> R
    ) rethrows -> R {
        try data.withUnsafeBytes(cb)
    }
}
