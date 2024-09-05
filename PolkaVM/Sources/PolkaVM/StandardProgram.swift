import Foundation

/// Standard Program defined in GP.
///
/// It includes some metadata for memory and registers initialization
/// other than the program code
public class StandardProgram {
    public enum Error: Swift.Error {
        case invalidStandardProgram
    }

    public enum Constants {
        public static let initReg1: UInt32 = (1 << 32) - (1 << 16)
        public static let stackBaseAddress: UInt32 = (1 << 32) - (2 * UInt32(DefaultPvmConfig().pvmProgramInitSegmentSize)) -
            UInt32(DefaultPvmConfig().pvmProgramInitInputDataSize)
        public static let inputStartAddress: UInt32 = (1 << 32) - UInt32(DefaultPvmConfig().pvmProgramInitSegmentSize) -
            UInt32(DefaultPvmConfig().pvmProgramInitInputDataSize)
    }

    public let code: ProgramCode
    public let initialMemory: Memory
    public let initialRegisters: Registers

    public init(blob: Data, argumentData: Data?) throws {
        var slice = Slice(base: blob, bounds: blob.startIndex ..< blob.endIndex)
        guard let readOnlyLen: UInt32 = slice.decode(length: 3) else {
            throw Error.invalidStandardProgram
        }
        guard let readWriteLen: UInt32 = slice.decode(length: 3) else {
            throw Error.invalidStandardProgram
        }
        guard let numPages: UInt16 = slice.decode(length: 2) else {
            throw Error.invalidStandardProgram
        }
        guard let stackSize: UInt32 = slice.decode(length: 3) else {
            throw Error.invalidStandardProgram
        }

        let readOnlyEndIdx = slice.startIndex + Int(readOnlyLen)
        guard readOnlyEndIdx <= slice.endIndex else {
            throw Error.invalidStandardProgram
        }
        let readOnlyData = blob[slice.startIndex ..< readOnlyEndIdx]

        let readWriteEndIdx = readOnlyEndIdx + Int(readWriteLen)
        guard readWriteEndIdx <= slice.endIndex else {
            throw Error.invalidStandardProgram
        }
        let readWriteData = blob[readOnlyEndIdx ..< readWriteEndIdx]

        slice = slice.dropFirst(Int(readOnlyLen) + Int(readWriteLen))

        guard let codeLength: UInt32 = slice.decode(length: 4), slice.startIndex + Int(codeLength) <= slice.endIndex else {
            throw Error.invalidStandardProgram
        }

        code = try ProgramCode(blob[relative: slice.startIndex ..< slice.startIndex + Int(codeLength)])

        initialRegisters = StandardProgram.initRegisters(argumentData: argumentData)
        // initialMemory = Memory(pageMap: pageMap, chunks: readWriteData)
    }

    static func initRegisters(argumentData: Data?) -> Registers {
        var registers = Registers()
        registers.reg1 = Constants.initReg1
        registers.reg2 = Constants.stackBaseAddress
        registers.reg10 = Constants.inputStartAddress
        registers.reg11 = UInt32(argumentData?.count ?? 0)
        return registers
    }
}
