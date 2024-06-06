public protocol ConstValue {
    associatedtype Value
    static var value: Value { get }
}

public protocol ConstInt: ConstValue where Value == Int {}

public protocol ConstUInt: ConstValue where Value == UInt {}

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

public enum ConstUInt128: ConstInt {
    public static var value: Int {
        128
    }
}

public enum ConstUInt144: ConstInt {
    public static var value: Int {
        144
    }
}
