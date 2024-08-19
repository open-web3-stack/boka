import Foundation
import ScaleCodec

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
    
    public func getCount() -> Int {
        return data.count;
    }
}

extension FixedSizeData: Equatable, Hashable {}

extension FixedSizeData: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "0x\(data.map { String(format: "%02x", $0) }.joined())"
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

extension FixedSizeData: ScaleCodec.Codable {
    public init(from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(decoder.decode(Data.self, .fixed(UInt(T.value))))!
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(data, .fixed(UInt(T.value)))
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
