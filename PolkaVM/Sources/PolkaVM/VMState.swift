import Foundation

public class VMState {
    public let program: ProgramCode

    public private(set) var instructionCounter: UInt32

    public private(set) var registers: Registers
    public private(set) var gas: Int64
    public private(set) var memory: Memory

    public init(program: ProgramCode, instructionCounter: UInt32, registers: Registers, gas: UInt64, memory: Memory) {
        self.program = program
        self.instructionCounter = instructionCounter
        self.registers = registers
        self.gas = Int64(gas)
        self.memory = memory
    }

    public func consumeGas(_ amount: UInt64) {
        gas -= Int64(amount)
    }
}
