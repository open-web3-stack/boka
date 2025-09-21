import CppHelper
import Foundation
import Utils

public class ProgramCode {
    public enum Error: Swift.Error {
        case invalidJumpTableEntriesCount
        case invalidJumpTableEncodeSize
        case invalidCodeLength
        case invalidDataLength
        case invalidInstruction
    }

    public enum Constants {
        public static let maxJumpTableEntriesCount: UInt64 = 0x100000
        public static let maxEncodeSize: UInt8 = 8
        public static let maxCodeLength: UInt64 = 0x400000
        public static let maxInstructionLength: UInt32 = 24
    }

    public let blob: Data
    public let jumpTableEntrySize: UInt8
    public let jumpTable: Data
    public let code: Data
    private let bitmask: Data

    // parsed stuff
    public private(set) var basicBlockIndices: Set<UInt32> = []

    private final class InstRef {
        let instruction: Instruction
        init(_ instruction: Instruction) {
            self.instruction = instruction
        }
    }

    private var instCache: [InstRef?] = []

    private var blockGasCosts: [UInt32: Gas] = [:]

    private static let cachedTrapInst = CppHelper.Instructions.Trap()

    public init(_ blob: Data) throws(Error) {
        self.blob = blob

        var slice = Slice(base: blob, bounds: blob.startIndex ..< blob.endIndex)
        guard let jumpTableEntriesCount = slice.decode(), jumpTableEntriesCount <= Constants.maxJumpTableEntriesCount else {
            throw Error.invalidJumpTableEntriesCount
        }
        guard let encodeSize = slice.next(), encodeSize <= Constants.maxEncodeSize else {
            throw Error.invalidJumpTableEncodeSize
        }
        guard let codeLength = slice.decode(), codeLength <= Constants.maxCodeLength else {
            throw Error.invalidCodeLength
        }

        jumpTableEntrySize = encodeSize

        let jumpTableSize = Int(jumpTableEntriesCount * UInt64(jumpTableEntrySize))
        let jumpTableEndIndex = slice.startIndex + jumpTableSize

        guard jumpTableEndIndex <= slice.endIndex else {
            throw Error.invalidDataLength
        }

        jumpTable = blob[slice.startIndex ..< jumpTableEndIndex]

        let codeEndIndex = jumpTableEndIndex + Int(codeLength)
        guard codeEndIndex <= slice.endIndex else {
            throw Error.invalidDataLength
        }

        code = blob[jumpTableEndIndex ..< codeEndIndex]

        let expectedBitmaskSize = (codeLength + 7) / 8

        guard expectedBitmaskSize == slice.endIndex - codeEndIndex else {
            throw Error.invalidDataLength
        }

        // mark bitmask bits longer than codeLength as 1
        var bitmaskData = blob[codeEndIndex ..< slice.endIndex]
        let fullBytes = Int(codeLength) / 8
        let remainingBits = Int(codeLength) % 8
        if remainingBits > 0 {
            let mask: UInt8 = ~0 << remainingBits
            bitmaskData[codeEndIndex + fullBytes] |= mask
        }
        bitmask = bitmaskData

        try buildMetadata()

        instCache = Array(repeating: nil, count: code.count)
    }

    private func buildMetadata() throws(Error) {
        var i = UInt32(0)
        basicBlockIndices.insert(0)
        var currentBlockStart = i
        var currentBlockGasCost = Gas(0)

        while i < code.count {
            let skip = ProgramCode.skip(start: i, bitmask: bitmask)

            let opcode = code[relative: Int(i)]
            currentBlockGasCost += gasFromOpcode(opcode)

            if BASIC_BLOCK_INSTRUCTIONS.contains(opcode) {
                // block end
                blockGasCosts[currentBlockStart] = currentBlockGasCost
                // next block
                basicBlockIndices.insert(i + skip + 1)
                currentBlockStart = i + skip + 1
                currentBlockGasCost = Gas(0)
            }
            i += skip + 1
        }
        blockGasCosts[currentBlockStart] = currentBlockGasCost + Gas(1)
        basicBlockIndices.insert(i)
    }

    private func gasFromOpcode(_: UInt8) -> Gas {
        // TODO: use a switch opcode later
        Gas(1)
    }

    private func parseInstruction(startIndex: Int, skip: UInt32) throws(Error) -> Instruction {
        let endIndex = startIndex + Int(skip) + 1
        let data = if endIndex <= code.endIndex {
            code[startIndex ..< endIndex]
        } else {
            code[startIndex ..< min(code.endIndex, endIndex)] + Data(repeating: 0, count: endIndex - code.endIndex)
        }
        guard let inst = InstructionTable.parse(data) else {
            throw Error.invalidInstruction
        }
        return inst
    }

    public func getInstructionAt(pc: UInt32) -> Instruction? {
        let pcIndex = Int(pc)

        if pcIndex >= instCache.count {
            return Self.cachedTrapInst
        }

        if let cached = instCache[pcIndex] {
            return cached.instruction
        }

        guard Int(pc) < code.count else {
            return Self.cachedTrapInst
        }

        do {
            let skip = skip(pc)
            let inst = try parseInstruction(startIndex: code.startIndex + Int(pc), skip: skip)
            instCache[pcIndex] = InstRef(inst)
            return inst
        } catch {
            return nil
        }
    }

    public func getBlockGasCosts(pc: UInt32) -> Gas {
        blockGasCosts[pc] ?? Gas(0)
    }

    public func skip(_ pc: UInt32) -> UInt32 {
        ProgramCode.skip(start: pc, bitmask: bitmask)
    }

    public static func skip(start: UInt32, bitmask: Data) -> UInt32 {
        let start = start + 1
        let beginIndex = Int(start / 8) + bitmask.startIndex
        guard beginIndex < bitmask.endIndex else {
            return 0
        }

        var value: UInt32 = 0
        if (beginIndex + 4) < bitmask.endIndex { // if enough bytes
            value = bitmask.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: beginIndex - bitmask.startIndex, as: UInt32.self) }
        } else {
            let byte1 = UInt32(bitmask[beginIndex])
            let byte2 = UInt32(bitmask[safe: beginIndex + 1] ?? 0xFF)
            let byte3 = UInt32(bitmask[safe: beginIndex + 2] ?? 0xFF)
            let byte4 = UInt32(bitmask[safe: beginIndex + 3] ?? 0xFF)
            value = byte1 | (byte2 << 8) | (byte3 << 16) | (byte4 << 24)
        }

        let offsetBits = start % 8

        let idx = min(UInt32((value >> offsetBits).trailingZeroBitCount), Constants.maxInstructionLength)

        return idx
    }
}

extension ProgramCode: Equatable {
    public static func == (lhs: ProgramCode, rhs: ProgramCode) -> Bool {
        lhs.blob == rhs.blob
    }
}
