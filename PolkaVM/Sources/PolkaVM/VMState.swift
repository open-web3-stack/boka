import Foundation
import Utils

public class VMState {
    public let program: ProgramCode

    public private(set) var pc: UInt32

    private var registers: Registers
    private var gas: GasInt
    private var memory: Memory

    public init(program: ProgramCode, pc: UInt32, registers: Registers, gas: Gas, memory: Memory) {
        self.program = program
        self.pc = pc
        self.registers = registers
        self.gas = GasInt(gas)
        self.memory = memory
    }

    /// Initialize from a standard program blob
    public init(standardProgramBlob blob: Data, pc: UInt32, gas: Gas, argumentData: Data?) throws {
        let program = try StandardProgram(blob: blob, argumentData: argumentData)
        self.program = program.code
        registers = program.initialRegisters
        memory = program.initialMemory
        self.pc = pc
        self.gas = GasInt(gas)
    }

    public func getRegisters() -> Registers {
        registers
    }

    public func getGas() -> GasInt {
        gas
    }

    public func getMemory() -> Memory.Readonly {
        Memory.Readonly(memory)
    }

    public func readMemory(address: some FixedWidthInteger) throws -> UInt8 {
        try memory.read(address: UInt32(truncatingIfNeeded: address))
    }

    public func readMemory(address: some FixedWidthInteger, length: Int) throws -> Data {
        try memory.read(address: UInt32(truncatingIfNeeded: address), length: length)
    }

    public func isMemoryReadable(address: some FixedWidthInteger, length: Int) -> Bool {
        memory.isReadable(address: UInt32(truncatingIfNeeded: address), length: length)
    }

    public func isMemoryWritable(address: some FixedWidthInteger, length: Int) -> Bool {
        memory.isWritable(address: UInt32(truncatingIfNeeded: address), length: length)
    }

    public func writeMemory(address: some FixedWidthInteger, value: UInt8) throws {
        try memory.write(address: UInt32(truncatingIfNeeded: address), value: value)
    }

    public func writeMemory(address: some FixedWidthInteger, values: some Sequence<UInt8>) throws {
        try memory.write(address: UInt32(truncatingIfNeeded: address), values: values)
    }

    public func sbrk(_ increment: UInt32) throws -> UInt32 {
        try memory.sbrk(increment)
    }

    public func consumeGas(_ amount: Gas) {
        gas -= GasInt(amount)
    }

    public func increasePC(_ amount: UInt32) {
        // using wrapped add
        // so that it can also be used for jumps which are negative
        pc &+= amount
    }

    public func updatePC(_ newPC: UInt32) {
        pc = newPC
    }

    public func readRegister<T: FixedWidthInteger>(_ index: Registers.Index) -> T {
        T(truncatingIfNeeded: registers[index])
    }

    public func readRegister<T: FixedWidthInteger>(_ index: Registers.Index, _ index2: Registers.Index) -> (T, T) {
        (T(truncatingIfNeeded: registers[index]), T(truncatingIfNeeded: registers[index2]))
    }

    public func readRegisters<T: FixedWidthInteger>(in range: Range<UInt8>) -> [T] {
        range.map { T(truncatingIfNeeded: registers[Registers.Index(raw: $0)]) }
    }

    public func writeRegister(_ index: Registers.Index, _ value: some FixedWidthInteger) {
        registers[index] = UInt64(truncatingIfNeeded: value)
    }
}
