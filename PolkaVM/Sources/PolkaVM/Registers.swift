import Foundation

public struct Registers: Equatable {
    public enum Error: Swift.Error {
        case invalidInitDataLength
    }

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

        public init(raw: UInt8) {
            value = raw
        }
    }

    public var reg1: UInt64 = 0
    public var reg2: UInt64 = 0
    public var reg3: UInt64 = 0
    public var reg4: UInt64 = 0
    public var reg5: UInt64 = 0
    public var reg6: UInt64 = 0
    public var reg7: UInt64 = 0
    public var reg8: UInt64 = 0
    public var reg9: UInt64 = 0
    public var reg10: UInt64 = 0
    public var reg11: UInt64 = 0
    public var reg12: UInt64 = 0
    public var reg13: UInt64 = 0

    public init() {}

    public init(_ values: [UInt64]) {
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

    /// standard program init registers
    public init(config: DefaultPvmConfig, argumentData: Data?) {
        self[Index(raw: 0)] = UInt64(config.pvmProgramInitRegister1Value)
        self[Index(raw: 1)] = UInt64(config.pvmProgramInitStackBaseAddress)
        self[Index(raw: 7)] = UInt64(config.pvmProgramInitInputStartAddress)
        self[Index(raw: 8)] = UInt64(argumentData?.count ?? 0)
    }

    public subscript(index: Index) -> UInt64 {
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

extension Registers: Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()

        var registers = [UInt64](repeating: 0, count: 13)
        for i in 0 ..< 13 {
            registers[i] = try container.decode(UInt64.self)
        }
        self.init(registers)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()

        for i in 0 ..< 13 {
            try container.encode(self[Registers.Index(raw: UInt8(i))])
        }
    }
}
