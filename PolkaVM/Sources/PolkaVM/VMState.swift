import Foundation
import TracingUtils
import Utils

public protocol VMState {
    // MARK: - Error Type

    typealias VMError = VMStateError

    // MARK: - Properties

    var program: ProgramCode { get }
    var pc: UInt32 { get }

    // MARK: - Methods

    // Register Operations
    func getRegisters() -> Registers
    func readRegister<T: FixedWidthInteger>(_ index: Registers.Index) -> T
    func readRegister<T: FixedWidthInteger>(_ index: Registers.Index, _ index2: Registers.Index) -> (T, T)
    func readRegisters<T: FixedWidthInteger>(in range: Range<UInt8>) -> [T]
    func writeRegister(_ index: Registers.Index, _ value: some FixedWidthInteger)

    // Memory Operations
    func getMemory() -> ReadonlyMemory
    func getMemoryUnsafe() -> GeneralMemory
    func isMemoryReadable(address: some FixedWidthInteger, length: Int) -> Bool
    func isMemoryWritable(address: some FixedWidthInteger, length: Int) -> Bool
    func readMemory(address: some FixedWidthInteger) throws -> UInt8
    func readMemory(address: some FixedWidthInteger, length: Int) throws -> Data
    func writeMemory(address: some FixedWidthInteger, value: UInt8) throws
    func writeMemory(address: some FixedWidthInteger, values: some Sequence<UInt8>) throws
    func sbrk(_ increment: UInt32) throws -> UInt32

    // VM State Control
    func getGas() -> GasInt
    func consumeGas(_ amount: Gas)
    func increasePC(_ amount: UInt32)
    func updatePC(_ newPC: UInt32)

    // Execution Control
    func withExecutingInst<R>(_ block: () throws -> R) rethrows -> R
}

public enum VMStateError: Error {
    case invalidInstructionMemoryAccess
}
