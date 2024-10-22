import Codec
import Foundation

public struct FixedSizeData<T: ConstInt>: Sendable {
    public private(set) var data: Data

    public init?(_ value: Data) {
        guard value.count == T.value else {
            return nil
        }
        data = value
    }

    public init() {
        data = Data(repeating: 0, count: T.value)
    }
}

extension FixedSizeData: Equatable, Hashable {}

extension FixedSizeData: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        data = try container.decode(Data.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(data)
    }
}

extension FixedSizeData: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        if T.value > 32 {
            let prefix = data.prefix(8).map { String(format: "%02x", $0) }.joined()
            let suffix = data.suffix(8).map { String(format: "%02x", $0) }.joined()
            return "0x\(prefix)...\(suffix) (\(data.count) bytes)"
        } else {
            return "0x\(data.map { String(format: "%02x", $0) }.joined())"
        }
    }

    public var debugDescription: String {
        description
    }
}

extension FixedSizeData: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        guard lhs.data.count == rhs.data.count else {
            return lhs.data.count < rhs.data.count
        }
        for (l, r) in zip(lhs.data, rhs.data) where l != r {
            return l < r
        }
        return false
    }
}

extension FixedSizeData: FixedLengthData {
    public static func length(decoder _: Decoder) -> Int {
        T.value
    }

    public init(decoder: Decoder, data: Data) throws {
        guard data.count == T.value else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Not enough data to decode \(T.self)"
                )
            )
        }
        self.data = data
    }
}

extension FixedSizeData: EncodedSize {
    public var encodedSize: Int {
        T.value
    }

    public static var encodeedSizeHint: Int? {
        T.value
    }
}

extension FixedSizeData {
    public static func random() -> Self {
        var data = Data(count: T.value)
        var generator = SystemRandomNumberGenerator()

        data.withUnsafeMutableBytes { ptr in
            for i in stride(from: 0, to: T.value, by: 8) {
                let randomValue = generator.next()
                let bytesToCopy = min(8, T.value - i)
                withUnsafeBytes(of: randomValue) { randomBytes in
                    UnsafeMutableRawBufferPointer(rebasing: ptr[i ..< (i + bytesToCopy)])
                        .copyMemory(from: UnsafeRawBufferPointer(rebasing: randomBytes[..<bytesToCopy]))
                }
            }
        }

        return Self(data)!
    }
}

public typealias Data32 = FixedSizeData<ConstInt32>
public typealias Data48 = FixedSizeData<ConstInt48>
public typealias Data64 = FixedSizeData<ConstInt64>
public typealias Data96 = FixedSizeData<ConstUInt96>
public typealias Data128 = FixedSizeData<ConstUInt128>
public typealias Data144 = FixedSizeData<ConstUInt144>
public typealias Data384 = FixedSizeData<ConstUInt384>
public typealias Data784 = FixedSizeData<ConstUInt784>
