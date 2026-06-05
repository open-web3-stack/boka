import Codec
import Foundation
import Utils

/// Standard Program defined in GP.
///
/// It includes some metadata for memory and registers initialization
/// other than the program code
public class StandardProgram {
    public enum Error: Swift.Error {
        case invalidReadOnlyLength
        case invalidReadWriteLength
        case invalidHeapPages
        case invalidStackSize
        case invalidDataLength
        case invalidCodeLength
        case invalidTotalMemorySize
    }

    public let code: ProgramCode
    public let initialMemory: Memory
    public let initialRegisters: Registers

    public convenience init(blob: Data, argumentData: Data?) throws {
        try self.init(template: StandardProgramTemplate(blob: blob), argumentData: argumentData)
    }

    fileprivate init(template: StandardProgramTemplate, argumentData: Data?) throws {
        code = ProgramCode(copying: template.code)

        initialRegisters = Registers(config: template.config, argumentData: argumentData)

        initialMemory = try StandardMemory(
            readOnlyData: template.readOnlyData,
            readWriteData: template.readWriteData,
            argumentData: argumentData ?? Data(),
            heapEmptyPagesSize: template.heapEmptyPagesSize,
            stackSize: template.stackSize,
        )
    }

    public static func cached(blob: Data, argumentData: Data?) throws -> StandardProgram {
        try StandardProgramCache.shared.program(blob: blob, argumentData: argumentData)
    }

    public static func alignToPageSize(size: UInt32, config: PvmConfig) -> UInt32 {
        let pageSize = UInt32(config.pvmMemoryPageSize)
        return (size + pageSize - 1) / pageSize * pageSize
    }

    public static func alignToZoneSize(size: UInt32, config: PvmConfig) -> UInt32 {
        let zoneSize = UInt32(config.pvmProgramInitZoneSize)
        return (size + zoneSize - 1) / zoneSize * zoneSize
    }
}

private final class StandardProgramTemplate: @unchecked Sendable {
    let code: ProgramCode
    let readOnlyData: Data
    let readWriteData: Data
    let heapEmptyPagesSize: UInt32
    let stackSize: UInt32
    let config: PvmConfig

    init(blob: Data) throws {
        // Data is already thread-safe (value semantic, copy-on-write)
        var slice = Slice(base: blob, bounds: blob.startIndex ..< blob.endIndex)

        guard let readOnlyLen: UInt32 = slice.decode(length: 3) else { throw StandardProgram.Error.invalidReadOnlyLength }
        guard let readWriteLen: UInt32 = slice.decode(length: 3) else { throw StandardProgram.Error.invalidReadWriteLength }
        guard let heapPages: UInt16 = slice.decode(length: 2) else { throw StandardProgram.Error.invalidHeapPages }
        guard let stackSize: UInt32 = slice.decode(length: 3) else { throw StandardProgram.Error.invalidStackSize }

        let readOnlyEndIdx = slice.startIndex + Int(readOnlyLen)
        guard readOnlyEndIdx <= slice.endIndex else { throw StandardProgram.Error.invalidDataLength }
        let readOnlyData = blob[slice.startIndex ..< readOnlyEndIdx]

        let readWriteEndIdx = readOnlyEndIdx + Int(readWriteLen)
        guard readWriteEndIdx <= slice.endIndex else { throw StandardProgram.Error.invalidDataLength }
        let readWriteData = blob[readOnlyEndIdx ..< readWriteEndIdx]

        slice = slice.dropFirst(Int(readOnlyLen + readWriteLen))
        guard let codeLength: UInt32 = slice.decode(length: 4), slice.startIndex + Int(codeLength) <= slice.endIndex else {
            throw StandardProgram.Error.invalidCodeLength
        }

        let config = DefaultPvmConfig()

        let Q = StandardProgram.alignToZoneSize
        let ZZ = config.pvmProgramInitZoneSize
        let ZP = config.pvmMemoryPageSize
        let ZI = config.pvmProgramInitInputDataSize
        let readOnlyAlignedSize = Int(Q(readOnlyLen, config))
        let heapEmptyPagesSize = Int(heapPages) * ZP
        let readWriteAlignedSize = Int(Q(readWriteLen + UInt32(heapEmptyPagesSize), config))
        let stackAlignedSize = Int(Q(stackSize, config))

        let totalSize = 5 * ZZ + readOnlyAlignedSize + readWriteAlignedSize + stackAlignedSize + ZI
        guard totalSize <= 0x1_0000_0000 else {
            throw StandardProgram.Error.invalidTotalMemorySize
        }
        // CRITICAL: Create a new Data object with indices starting from 0
        // ProgramCode expects blob.startIndex to be 0, not an offset into the original blob
        // Using Array to ensure we get a copy with zero-based indices
        let programCodeBytes = Array(blob[slice.startIndex ..< slice.startIndex + Int(codeLength)])
        let programCodeData = Data(programCodeBytes)
        code = try ProgramCode(programCodeData)

        self.readOnlyData = readOnlyData
        self.readWriteData = readWriteData
        self.heapEmptyPagesSize = UInt32(heapEmptyPagesSize)
        self.stackSize = UInt32(stackSize)
        self.config = config
    }
}

private final class StandardProgramCache: @unchecked Sendable {
    static let shared = StandardProgramCache()

    private let lock = ReadWriteLock()
    private var templates: [Data: StandardProgramTemplate] = [:]
    private var insertionOrder: [Data] = []
    private let maxEntries = 64

    func program(blob: Data, argumentData: Data?) throws -> StandardProgram {
        if let template = lock.withReadLock({ templates[blob] }) {
            return try StandardProgram(template: template, argumentData: argumentData)
        }

        let parsedTemplate = try StandardProgramTemplate(blob: blob)
        let template = lock.withWriteLock {
            if let existing = templates[blob] {
                return existing
            }

            templates[blob] = parsedTemplate
            insertionOrder.append(blob)

            if insertionOrder.count > maxEntries {
                let evicted = insertionOrder.removeFirst()
                templates.removeValue(forKey: evicted)
            }

            return parsedTemplate
        }

        return try StandardProgram(template: template, argumentData: argumentData)
    }
}
