import Codec
import CppHelper
import Foundation
import TracingUtils
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
    private let bitmaskArray: [UInt8]

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
    private static let logger = Logger(label: "ProgramCode")

    public init(_ blob: Data) throws (Error) {
        self.blob = blob

        var slice = Slice(base: blob, bounds: blob.startIndex ..< blob.endIndex)
        guard let jumpTableEntriesCount = slice.decode(), jumpTableEntriesCount <= Constants.maxJumpTableEntriesCount else {
            throw Error.invalidJumpTableEntriesCount
        }
        guard let encodeSize = slice.next(), encodeSize <= Constants.maxEncodeSize else {
            throw Error.invalidJumpTableEncodeSize
        }

        // Decode codeLength using the same spec-compliant decoder as jumpTableEntriesCount
        // Format from serialization.tex: variable-length encoding with prefix bytes
        guard let codeLength = slice.decode(), codeLength <= Constants.maxCodeLength else {
            throw Error.invalidCodeLength
        }

        jumpTableEntrySize = encodeSize

        let jumpTableSize = Int(jumpTableEntriesCount * UInt64(jumpTableEntrySize))
        let jumpTableEndIndex = slice.startIndex + jumpTableSize

        guard jumpTableEndIndex <= slice.endIndex else {
            Self.logger
                .error(
                    "Jump table extends beyond blob: jumpTableSize=\(jumpTableSize), startIndex=\(slice.startIndex), endIndex=\(jumpTableEndIndex), slice.endIndex=\(slice.endIndex)"
                )
            throw Error.invalidDataLength
        }

        jumpTable = blob[slice.startIndex ..< jumpTableEndIndex]

        let codeEndIndex = jumpTableEndIndex + Int(codeLength)
        guard codeEndIndex <= slice.endIndex else {
            Self.logger
                .error(
                    "Code extends beyond blob: codeLength=\(codeLength), jumpTableEndIndex=\(jumpTableEndIndex), codeEndIndex=\(codeEndIndex), slice.endIndex=\(slice.endIndex)"
                )
            throw Error.invalidDataLength
        }

        code = blob[jumpTableEndIndex ..< codeEndIndex]

        let expectedBitmaskSize = (codeLength + 7) / 8
        let actualBitmaskSize = slice.endIndex - codeEndIndex

        guard expectedBitmaskSize == actualBitmaskSize else {
            Self.logger
                .error(
                    "Bitmask size mismatch: codeLength=\(codeLength), expected=\(expectedBitmaskSize), actual=\(actualBitmaskSize), blob.count=\(blob.count), jumpTableEndIndex=\(jumpTableEndIndex), codeEndIndex=\(codeEndIndex), slice.startIndex=\(slice.startIndex), slice.endIndex=\(slice.endIndex)"
                )
            throw Error.invalidDataLength
        }

        // mark bitmask bits longer than codeLength as 1
        // Note: The blob bitmask should already have this applied correctly
        // Store as Array to avoid Data lifetime issues
        let bitmaskSlice = blob[codeEndIndex ..< slice.endIndex]
        bitmaskArray = Array(bitmaskSlice)

        try buildMetadata()

        instCache = Array(repeating: nil, count: code.count)
    }

    private func buildMetadata() throws (Error) {
        var i = UInt32(0)
        basicBlockIndices.insert(0)
        var currentBlockStart = i
        var currentBlockGasCost = Gas(0)

        while i < code.count {
            let skip = ProgramCode.skip(start: i, bitmask: Data(bitmaskArray))

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

    private func parseInstruction(startIndex: Int, skip: UInt32) throws (Error) -> Instruction {
        let endIndex = startIndex + Int(skip) + 1
        let data: Data = if endIndex <= code.endIndex {
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
        ProgramCode.skip(start: pc, bitmask: Data(bitmaskArray))
    }

    /// Extract all skip values as an array for JIT compilation
    /// This provides the instruction sizes for variable-length encoded instructions.
    ///
    /// Memory Trade-off: This array uses 4 bytes per instruction byte (4x code size).
    /// For a 100KB program, this adds ~400KB of memory. This is acceptable because:
    /// 1. It's only computed once during program loading
    /// 2. It's freed after JIT compilation completes
    /// 3. It's significantly faster than on-demand calculation from C++
    ///
    /// Alternative: Could calculate on-demand in C++ to save memory, but would add
    /// complexity to the Swift/C++ boundary and slow down compilation.
    public var skipValues: [UInt32] {
        var skips: [UInt32] = []
        skips.reserveCapacity(code.count)
        for pc in 0 ..< UInt32(code.count) {
            let skip = skip(pc)
            skips.append(skip)
        }
        return skips
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
