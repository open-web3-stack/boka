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

public enum ConstInt12: ConstInt {
    public static var value: Int {
        12
    }
}

public enum ConstInt31: ConstInt {
    public static var value: Int {
        31
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

public enum ConstInt96: ConstInt {
    public static var value: Int {
        96
    }
}

public enum ConstInt128: ConstInt {
    public static var value: Int {
        128
    }
}

public enum ConstInt144: ConstInt {
    public static var value: Int {
        144
    }
}

public enum ConstInt384: ConstInt {
    public static var value: Int {
        384
    }
}

public enum ConstInt784: ConstInt {
    public static var value: Int {
        784
    }
}

public enum ConstInt4104: ConstInt {
    public static var value: Int {
        4104
    }
}

public enum ConstIntMax: ConstInt {
    public static var value: Int {
        Int.max
    }
}
