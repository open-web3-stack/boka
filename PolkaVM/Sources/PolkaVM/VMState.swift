import Foundation
import Numerics

public class VMState {
    public let program: ProgramCode

    public private(set) var pc: UInt32

    private var registers: Registers
    private var gas: Int64
    private var memory: Memory

    public init(program: ProgramCode, pc: UInt32, registers: Registers, gas: UInt64, memory: Memory) {
        self.program = program
        self.pc = pc
        self.registers = registers
        self.gas = Int64(gas)
        self.memory = memory
    }

    /// Initialize from a standard program blob
    public init(standardProgramBlob blob: Data, pc: UInt32, gas: UInt64, argumentData: Data?) throws {
        let program = try StandardProgram(blob: blob, argumentData: argumentData)
        self.program = program.code
        registers = program.initialRegisters
        memory = program.initialMemory
        self.pc = pc
        self.gas = Int64(gas)
    }

    public func getRegisters() -> Registers {
        registers
    }

    public func getGas() -> Int64 {
        gas
    }

    public func getMemory() -> Memory.Readonly {
        Memory.Readonly(memory)
    }

    public func readMemory(address: UInt32) throws -> UInt8 {
        try memory.read(address: address)
    }

    public func readMemory(address: UInt32, length: Int) throws -> Data {
        try memory.read(address: address, length: length)
    }

    public func isMemoryReadable(address: UInt32, length: Int) -> Bool {
        memory.isReadable(address: address, length: length)
    }

    public func isMemoryWritable(address: UInt32, length: Int) -> Bool {
        memory.isWritable(address: address, length: length)
    }

    public func writeMemory(address: UInt32, value: UInt8) throws {
        try memory.write(address: address, value: value)
    }

    public func writeMemory(address: UInt32, values: some Sequence<UInt8>) throws {
        try memory.write(address: address, values: values)
    }

    public func sbrk(_ increment: UInt32) throws -> UInt32 {
        try memory.sbrk(increment)
    }

    public func consumeGas(_ amount: UInt64) {
        gas = gas.subtractingWithSaturation(Int64(amount))
    }

    public func increasePC(_ amount: UInt32) {
        // using wrapped add
        // so that it can also be used for jumps which are negative
        pc &+= amount
    }

    public func updatePC(_ newPC: UInt32) {
        pc = newPC
    }

    public func readRegister(_ index: Registers.Index) -> UInt32 {
        registers[index]
    }

    public func readRegister(_ index: Registers.Index, _ index2: Registers.Index) -> (UInt32, UInt32) {
        (registers[index], registers[index2])
    }

    public func readRegisters(in range: Range<UInt8>) -> [UInt32] {
        range.map { registers[Registers.Index(raw: $0)] }
    }

    public func writeRegister(_ index: Registers.Index, _ value: UInt32) {
        registers[index] = value
    }
}
