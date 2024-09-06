import Foundation

/// Standard Program defined in GP.
///
/// It includes some metadata for memory and registers initialization
/// other than the program code
public class StandardProgram {
    public enum Error: Swift.Error {
        case invalidReadOnlyLength
        case invalidReadWriteLength
        case invalidNumPages
        case invalidStackSize
        case invalidDataLength
        case invalidCodeLength
        case invalidTotalMemorySize
    }

    public let code: ProgramCode
    public let initialMemory: Memory
    public let initialRegisters: Registers

    public init(blob: Data, argumentData: Data?) throws {
        var slice = Slice(base: blob, bounds: blob.startIndex ..< blob.endIndex)
        guard let readOnlyLen: UInt32 = slice.decode(length: 3) else { throw Error.invalidReadOnlyLength }
        guard let readWriteLen: UInt32 = slice.decode(length: 3) else { throw Error.invalidReadWriteLength }
        guard let numPages: UInt16 = slice.decode(length: 2) else { throw Error.invalidNumPages }
        guard let stackSize: UInt32 = slice.decode(length: 3) else { throw Error.invalidStackSize }

        let readOnlyEndIdx = slice.startIndex + Int(readOnlyLen)
        guard readOnlyEndIdx <= slice.endIndex else { throw Error.invalidDataLength }
        let readOnlyData = blob[slice.startIndex ..< readOnlyEndIdx]

        let readWriteEndIdx = readOnlyEndIdx + Int(readWriteLen)
        guard readWriteEndIdx <= slice.endIndex else { throw Error.invalidDataLength }
        let readWriteData = blob[readOnlyEndIdx ..< readWriteEndIdx]

        slice = slice.dropFirst(Int(readOnlyLen) + Int(readWriteLen))

        guard let codeLength: UInt32 = slice.decode(length: 4), slice.startIndex + Int(codeLength) <= slice.endIndex else {
            throw Error.invalidCodeLength
        }

        let config = DefaultPvmConfig()

        let P = StandardProgram.alignToPageSize
        let Q = StandardProgram.alignToSegmentSize
        let ZP = config.pvmProgramInitPageSize
        let ZQ = config.pvmProgramInitSegmentSize
        let ZI = config.pvmProgramInitInputDataSize
        let totalSegmentSize = 5 * ZQ
        let readOnlyAlignedSize = Int(Q(readOnlyLen, config))
        let totalPageMapSize = Int(numPages) * ZP
        let readWriteAlignedSize = Int(Q(readWriteLen + UInt32(totalPageMapSize), config))
        let stackAlignedSize = Int(Q(stackSize, config))

        let totalSize = totalSegmentSize + readOnlyAlignedSize + readWriteAlignedSize + stackAlignedSize + ZI
        guard totalSize <= Int32.max else {
            throw Error.invalidTotalMemorySize
        }

        code = try ProgramCode(blob[relative: slice.startIndex ..< slice.startIndex + Int(codeLength)])

        initialRegisters = Registers(config: config, argumentData: argumentData)

        // initialMemory = Memory(
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
