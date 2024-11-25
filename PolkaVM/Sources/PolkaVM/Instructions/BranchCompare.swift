protocol BranchCompare {
    static func compare(a: UInt64, b: UInt64) -> Bool
}

struct CompareEq: BranchCompare {
    static func compare(a: UInt64, b: UInt64) -> Bool {
        Int64(bitPattern: a) == Int64(bitPattern: b)
    }
}

struct CompareNe: BranchCompare {
    static func compare(a: UInt64, b: UInt64) -> Bool {
        Int64(bitPattern: a) != Int64(bitPattern: b)
    }
}

struct CompareLtU: BranchCompare {
    static func compare(a: UInt64, b: UInt64) -> Bool {
        a < b
    }
}

struct CompareLtS: BranchCompare {
    static func compare(a: UInt64, b: UInt64) -> Bool {
        Int64(bitPattern: a) < Int64(bitPattern: b)
    }
}

struct CompareLeU: BranchCompare {
    static func compare(a: UInt64, b: UInt64) -> Bool {
        a <= b
    }
}

struct CompareLeS: BranchCompare {
    static func compare(a: UInt64, b: UInt64) -> Bool {
        Int64(bitPattern: a) <= Int64(bitPattern: b)
    }
}

struct CompareGeU: BranchCompare {
    static func compare(a: UInt64, b: UInt64) -> Bool {
        a >= b
    }
}

struct CompareGeS: BranchCompare {
    static func compare(a: UInt64, b: UInt64) -> Bool {
        Int64(bitPattern: a) >= Int64(bitPattern: b)
    }
}

struct CompareGtU: BranchCompare {
    static func compare(a: UInt64, b: UInt64) -> Bool {
        a > b
    }
}

struct CompareGtS: BranchCompare {
    static func compare(a: UInt64, b: UInt64) -> Bool {
        Int64(bitPattern: a) > Int64(bitPattern: b)
    }
}
