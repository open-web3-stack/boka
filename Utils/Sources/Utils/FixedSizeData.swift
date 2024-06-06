import Foundation

public struct FixedSizeData<T: ConstInt> {
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

extension FixedSizeData: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "0x\(data.map { String(format: "%02x", $0) }.joined())"
    }

    public var debugDescription: String {
        description
    }
}

public typealias Data32 = FixedSizeData<ConstInt32>
public typealias Data64 = FixedSizeData<ConstInt64>
public typealias Data96 = FixedSizeData<ConstUInt96>
public typealias Data128 = FixedSizeData<ConstUInt128>
public typealias Data144 = FixedSizeData<ConstUInt144>
