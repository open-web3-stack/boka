protocol BranchCompare {
    static func compare(a: UInt32, b: UInt32) -> Bool
}

struct CompareEq: BranchCompare {
    static func compare(a: UInt32, b: UInt32) -> Bool {
        Int32(bitPattern: a) == Int32(bitPattern: b)
    }
}

struct CompareNe: BranchCompare {
    static func compare(a: UInt32, b: UInt32) -> Bool {
        Int32(bitPattern: a) != Int32(bitPattern: b)
    }
}

struct CompareLtU: BranchCompare {
    static func compare(a: UInt32, b: UInt32) -> Bool {
        a < b
    }
}

struct CompareLtS: BranchCompare {
    static func compare(a: UInt32, b: UInt32) -> Bool {
        Int32(bitPattern: a) < Int32(bitPattern: b)
    }
}

struct CompareLeU: BranchCompare {
    static func compare(a: UInt32, b: UInt32) -> Bool {
        a <= b
    }
}

struct CompareLeS: BranchCompare {
    static func compare(a: UInt32, b: UInt32) -> Bool {
        Int32(bitPattern: a) <= Int32(bitPattern: b)
    }
}

struct CompareGeU: BranchCompare {
    static func compare(a: UInt32, b: UInt32) -> Bool {
        a >= b
    }
}

struct CompareGeS: BranchCompare {
    static func compare(a: UInt32, b: UInt32) -> Bool {
        Int32(bitPattern: a) >= Int32(bitPattern: b)
    }
}

struct CompareGtU: BranchCompare {
    static func compare(a: UInt32, b: UInt32) -> Bool {
        a > b
    }
}

struct CompareGtS: BranchCompare {
    static func compare(a: UInt32, b: UInt32) -> Bool {
        Int32(bitPattern: a) > Int32(bitPattern: b)
    }
}
