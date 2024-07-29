public struct Registers: Equatable {
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
}
