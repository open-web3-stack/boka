import Foundation

public struct FixedSizeData<T: ConstInt> {
    // TODO: completly hide data and only allow access via protocol methods
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

public enum ConstInt32: ConstInt {
    public static var value: Int {
        32
    }
}

public enum ConstInt64: ConstInt {
    public static var value: Int {
        64
    }
}

public enum ConstUInt96: ConstInt {
    public static var value: Int {
        96
    }
}

public typealias Data32 = FixedSizeData<ConstInt32>
public typealias Data64 = FixedSizeData<ConstInt64>
public typealias Data96 = FixedSizeData<ConstUInt96>
