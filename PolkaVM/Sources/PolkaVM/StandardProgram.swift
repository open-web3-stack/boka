import Foundation

/// Standard Program defined in GP.
///
/// It includes some metadata for memory and registers initialization
/// other than the program code
public class StandardProgram {
    public enum Error: Swift.Error {
        case invalidStandardProgram
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

        let config = DefaultPvmConfig()
        // guard

        code = try ProgramCode(blob[relative: slice.startIndex ..< slice.startIndex + Int(codeLength)])

        initialRegisters = Registers(config: config, argumentData: argumentData)
    }

    static func alignToPageSize(size: UInt32, config: PvmConfig) -> UInt32 {
        let pageSize = UInt32(config.pvmProgramInitPageSize)
        return (size + pageSize - 1) / pageSize * pageSize
    }

    static func alignToSegmentSize(size: UInt32, config: PvmConfig) -> UInt32 {
        let segmentSize = UInt32(config.pvmProgramInitSegmentSize)
        return (size + segmentSize - 1) / segmentSize * segmentSize
    }
}
