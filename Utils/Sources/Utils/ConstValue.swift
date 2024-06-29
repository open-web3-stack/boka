public protocol ConstValue {
    associatedtype Value
    static var value: Value { get }
}

public protocol ConstInt: ConstValue where Value == Int {}

public protocol ConstUInt: ConstValue where Value == UInt {}

public enum ConstInt0: ConstInt {
    public static var value: Int {
        0
    }
}

public enum ConstInt1: ConstInt {
    public static var value: Int {
        1
    }
}

public enum ConstInt2: ConstInt {
    public static var value: Int {
        2
    }
}

public enum ConstInt3: ConstInt {
    public static var value: Int {
        3
    }
}

public enum ConstIntMax: ConstInt {
    public static var value: Int {
        Int.max
    }
}

public enum ConstInt32: ConstInt {
    public static var value: Int {
        32
    }
}

public enum ConstInt48: ConstInt {
    public static var value: Int {
        48
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

public enum ConstUInt784: ConstInt {
    public static var value: Int {
        784
    }
}
