import Foundation

public struct Registers: Equatable {
    public struct Index {
        public let value: UInt8
        public init(ra: UInt8) {
            value = min(ra & 0b1111, 12)
        }

        public init(rb: UInt8) {
            value = min(rb >> 4, 12)
        }

        public init(rd: UInt8) {
            value = min(rd, 12)
        }
    }

    public var reg1: UInt32 = 0
    public var reg2: UInt32 = 0
    public var reg3: UInt32 = 0
    public var reg4: UInt32 = 0
    public var reg5: UInt32 = 0
    public var reg6: UInt32 = 0
    public var reg7: UInt32 = 0
    public var reg8: UInt32 = 0
    public var reg9: UInt32 = 0
    public var reg10: UInt32 = 0
    public var reg11: UInt32 = 0
    public var reg12: UInt32 = 0
    public var reg13: UInt32 = 0

    public init() {}

    public init(_ values: [UInt32]) {
        assert(values.count == 13)
        reg1 = values[0]
        reg2 = values[1]
        reg3 = values[2]
        reg4 = values[3]
        reg5 = values[4]
        reg6 = values[5]
        reg7 = values[6]
        reg8 = values[7]
        reg9 = values[8]
        reg10 = values[9]
        reg11 = values[10]
        reg12 = values[11]
        reg13 = values[12]
    }

    /// standard program init
    public init(config: DefaultPvmConfig, argumentData: Data?) {
        reg1 = UInt32(config.pvmProgramInitRegister1Value)
        reg2 = UInt32(config.pvmProgramInitStackBaseAddress)
        reg10 = UInt32(config.pvmProgramInitInputStartAddress)
        reg11 = UInt32(argumentData?.count ?? 0)
    }

    public subscript(index: Index) -> UInt32 {
        get {
            switch index.value {
            case 0:
                reg1
            case 1:
                reg2
            case 2:
                reg3
            case 3:
                reg4
            case 4:
                reg5
            case 5:
                reg6
            case 6:
                reg7
            case 7:
                reg8
            case 8:
                reg9
            case 9:
                reg10
            case 10:
                reg11
            case 11:
                reg12
            case 12:
                reg13
            default:
                fatalError("unreachable: index out of bounds \(index.value)")
            }
        }
        set {
            switch index.value {
            case 0:
                reg1 = newValue
            case 1:
                reg2 = newValue
            case 2:
                reg3 = newValue
            case 3:
                reg4 = newValue
            case 4:
                reg5 = newValue
            case 5:
                reg6 = newValue
            case 6:
                reg7 = newValue
            case 7:
                reg8 = newValue
            case 8:
                reg9 = newValue
            case 9:
                reg10 = newValue
            case 10:
                reg11 = newValue
            case 11:
                reg12 = newValue
            case 12:
                reg13 = newValue
            default:
                fatalError("unreachable: index out of bounds \(index.value)")
            }
        }
    }
}
