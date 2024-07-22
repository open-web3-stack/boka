import Foundation

public class VMState {
    public let program: ProgramCode

    public private(set) var instructionCounter: UInt32

    public private(set) var registers: (
        UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32
    ) // 13 registers
    public private(set) var gas: UInt64
    public private(set) var memory: Data
}
