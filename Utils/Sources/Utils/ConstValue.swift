public protocol ConstValue {
    associatedtype Value
    static var value: Value { get }
}

public protocol ConstInt: ConstValue where Value == Int {}

public protocol ConstUInt: ConstValue where Value == UInt {}
