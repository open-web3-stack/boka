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

struct CompareLt: BranchCompare {
    static func compare(a: UInt32, b: UInt32) -> Bool {
        a < b
    }
}

struct CompareLe: BranchCompare {
    static func compare(a: UInt32, b: UInt32) -> Bool {
        a <= b
    }
}

struct CompareGe: BranchCompare {
    static func compare(a: UInt32, b: UInt32) -> Bool {
        a >= b
    }
}

struct CompareGt: BranchCompare {
    static func compare(a: UInt32, b: UInt32) -> Bool {
        a > b
    }
}
