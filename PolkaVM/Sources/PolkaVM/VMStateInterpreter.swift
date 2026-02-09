import Foundation
import Utils

public class VMStateInterpreter: VMState {
    public let program: ProgramCode

    private var _pc: UInt32

    public var pc: UInt32 {
        _pc
    }

    private var registers: Registers
    private var gas: GasInt
    private var memory: Memory

    private var isExecutingInst: Bool = false

    public init(program: ProgramCode, pc: UInt32, registers: Registers, gas: Gas, memory: Memory) {
        self.program = program
        _pc = pc
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
        _pc = pc
        self.gas = GasInt(gas)
    }

    public func getRegisters() -> Registers {
        registers
    }

    public func getGas() -> GasInt {
        gas
    }

    public func getMemory() -> ReadonlyMemory {
        ReadonlyMemory(memory)
    }

    public func getMemoryUnsafe() -> GeneralMemory {
        if let memory = memory as? GeneralMemory {
            memory
        } else {
            fatalError("cannot get memory of type \(type(of: memory))")
        }
    }

    public func isMemoryReadable(address: some FixedWidthInteger, length: Int) -> Bool {
        memory.isReadable(address: UInt32(truncatingIfNeeded: address), length: length)
    }

    /// During the course of executing instructions
    /// When an index of ram below 2^16 is required, the machine always panics immediately
    private func validateAddress(_ address: some FixedWidthInteger) throws {
        if isExecutingInst, UInt32(truncatingIfNeeded: address) < (1 << 16) {
            throw VMStateError.invalidInstructionMemoryAccess
        }
    }

    public func readMemory(address: some FixedWidthInteger) throws -> UInt8 {
        let addr = UInt32(truncatingIfNeeded: address)
        try validateAddress(addr)
        return try memory.read(address: addr)
    }

    public func readMemory(address: some FixedWidthInteger, length: Int) throws -> Data {
        if length == 0 { return Data() }
        let addr = UInt32(truncatingIfNeeded: address)
        try validateAddress(addr)
        return try memory.read(address: addr, length: length)
    }

    public func isMemoryWritable(address: some FixedWidthInteger, length: Int) -> Bool {
        memory.isWritable(address: UInt32(truncatingIfNeeded: address), length: length)
    }

    public func writeMemory(address: some FixedWidthInteger, value: UInt8) throws {
        let addr = UInt32(truncatingIfNeeded: address)
        try validateAddress(addr)
        try memory.write(address: addr, value: value)
    }

    public func writeMemory(address: some FixedWidthInteger, values: some Sequence<UInt8>) throws {
        let data = Data(values)
        guard !data.isEmpty else { return }
        let addr = UInt32(truncatingIfNeeded: address)
        try validateAddress(addr)
        try memory.write(address: addr, values: data)
    }

    public func writeMemory(address: some FixedWidthInteger, values: Data) throws {
        guard !values.isEmpty else { return }
        let addr = UInt32(truncatingIfNeeded: address)
        try validateAddress(addr)
        try memory.write(address: addr, values: values)
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
        _pc &+= amount
    }

    public func updatePC(_ newPC: UInt32) {
        _pc = newPC
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

    public func withExecutingInst<R>(_ block: () throws -> R) rethrows -> R {
        isExecutingInst = true
        defer { isExecutingInst = false }
        return try block()
    }
}
