import Foundation
import Utils

public class ProgramCode {
    public enum Error: Swift.Error {
        case invalidJumpTableEntriesCount
        case invalidJumpTableEncodeSize
        case invalidCodeLength
        case invalidDataLength
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

    public let basicBlockIndices: Set<UInt32>

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

        bitmask = blob[codeEndIndex ..< slice.endIndex]

        basicBlockIndices = ProgramCode.getBasicBlockIndices(code: code, bitmask: bitmask)
    }

    public static func skip(start: UInt32, bitmask: Data) -> UInt32 {
        let start = start + 1
        let beginIndex = Int(start / 8) + bitmask.startIndex
        guard beginIndex < bitmask.endIndex else {
            return 0
        }

        var value: UInt32 = 0
        if (beginIndex + 4) < bitmask.endIndex { // if enough bytes
            value = bitmask.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: beginIndex, as: UInt32.self) }
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

    public func skip(_ start: UInt32) -> UInt32 {
        ProgramCode.skip(start: start, bitmask: bitmask)
    }

    /// traverse the program code and collect basic block indices
    private static func getBasicBlockIndices(code: Data, bitmask: Data) -> Set<UInt32> {
        // TODO: parse the instructions here and so we don't need to do skip calculation multiple times
        var res: Set<UInt32> = [0]
        var i = UInt32(0)
        while i < code.count {
            let opcode = code[relative: Int(i)]
            let skip = ProgramCode.skip(start: i, bitmask: bitmask)
            if BASIC_BLOCK_INSTRUCTIONS.contains(opcode) {
                res.insert(i + skip + 1)
            }
            i += skip + 1
        }
        return res
    }
}

extension ProgramCode: Equatable {
    public static func == (lhs: ProgramCode, rhs: ProgramCode) -> Bool {
        lhs.blob == rhs.blob
    }
}
