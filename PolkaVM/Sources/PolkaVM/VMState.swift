import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "VMState ")

public class VMState {
    public enum VMError: Error {
        case invalidInstructionMemoryAccess
    }

    public let program: ProgramCode

    public private(set) var pc: UInt32

    private var registers: Registers
    private var gas: GasInt
    private var memory: Memory

    public var isExecutingInst: Bool = false

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

    // During the course of executing instructions
    // When an index of ram below 2^16 is required, the machine always panics immediately
    private func validateAddress(_ address: some FixedWidthInteger) throws {
        if isExecutingInst, UInt32(truncatingIfNeeded: address) < (1 << 16) {
            throw VMError.invalidInstructionMemoryAccess
        }
    }

    public func readMemory(address: some FixedWidthInteger) throws -> UInt8 {
        try validateAddress(address)
        let res = try memory.read(address: UInt32(truncatingIfNeeded: address))
        logger.trace("read  \(address) (\(res))")
        return res
    }

    public func readMemory(address: some FixedWidthInteger, length: Int) throws -> Data {
        try validateAddress(address)
        let res = try memory.read(address: UInt32(truncatingIfNeeded: address), length: length)
        logger.trace("read  \(address)..+\(length) (\(res))")
        return res
    }

    public func isMemoryWritable(address: some FixedWidthInteger, length: Int) -> Bool {
        memory.isWritable(address: UInt32(truncatingIfNeeded: address), length: length)
    }

    public func writeMemory(address: some FixedWidthInteger, value: UInt8) throws {
        try validateAddress(address)
        logger.trace("write \(address) (\(value))")
        try memory.write(address: UInt32(truncatingIfNeeded: address), value: value)
    }

    public func writeMemory(address: some FixedWidthInteger, values: some Sequence<UInt8>) throws {
        try validateAddress(address)
        logger.trace("write \(address) (\(values))")
        try memory.write(address: UInt32(truncatingIfNeeded: address), values: Data(values))
    }

    public func sbrk(_ increment: UInt32) throws -> UInt32 {
        try memory.sbrk(increment)
    }

    public func consumeGas(_ amount: Gas) {
        gas -= GasInt(amount)
        logger.trace("gas   -  \(amount) => \(gas)")
    }

    public func increasePC(_ amount: UInt32) {
        // using wrapped add
        // so that it can also be used for jumps which are negative
        pc &+= amount
        logger.trace("pc    &+ \(amount) => \(pc)")
    }

    public func updatePC(_ newPC: UInt32) {
        pc = newPC
        logger.trace("pc    => \(pc)")
    }

    public func readRegister<T: FixedWidthInteger>(_ index: Registers.Index) -> T {
        logger.trace("read  w\(index.value) (\(registers[index]))")
        return T(truncatingIfNeeded: registers[index])
    }

    public func readRegister<T: FixedWidthInteger>(_ index: Registers.Index, _ index2: Registers.Index) -> (T, T) {
        logger.trace("read  w\(index.value) (\(registers[index]))  w\(index2.value) (\(registers[index2]))")
        return (T(truncatingIfNeeded: registers[index]), T(truncatingIfNeeded: registers[index2]))
    }

    public func readRegisters<T: FixedWidthInteger>(in range: Range<UInt8>) -> [T] {
        _ = range.map { logger.trace("read  w\($0) (\(T(truncatingIfNeeded: registers[Registers.Index(raw: $0)])))") }
        return range.map { T(truncatingIfNeeded: registers[Registers.Index(raw: $0)]) }
    }

    public func writeRegister(_ index: Registers.Index, _ value: some FixedWidthInteger) {
        logger.trace("write w\(index.value) (\(value))")
        registers[index] = UInt64(truncatingIfNeeded: value)
    }
}
