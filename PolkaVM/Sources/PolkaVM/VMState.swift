import Foundation

public class VMState {
    public let program: ProgramCode

    public private(set) var pc: UInt32

    public private(set) var registers: Registers
    public private(set) var gas: Int64
    public private(set) var memory: Memory

    public init(program: ProgramCode, pc: UInt32, registers: Registers, gas: UInt64, memory: Memory) {
        self.program = program
        self.pc = pc
        self.registers = registers
        self.gas = Int64(gas)
        self.memory = memory
    }

    public func consumeGas(_ amount: UInt64) {
        // TODO: use saturating subtraction
        gas -= Int64(amount)
    }

    public func increasePC(_ amount: UInt32) {
        // using wrapped add
        // so that it can also be used for jumps which are negative
        pc &+= amount
    }
}
