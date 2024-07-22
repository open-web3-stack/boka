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
        public static let maxInstructionLength: UInt = 24
    }

    public let blob: Data
    private let jumpTableEntrySize: UInt8
    private let jumpTable: Slice<Data>
    private let code: Slice<Data>
    private let bitmask: Slice<Data>

    public init(_ blob: Data) throws {
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

        jumpTable = Slice(base: blob, bounds: slice.startIndex ..< jumpTableEndIndex)

        let codeEndIndex = jumpTableEndIndex + Int(codeLength)
        guard codeEndIndex <= slice.endIndex else {
            throw Error.invalidDataLength
        }

        code = Slice(base: blob, bounds: jumpTableEndIndex ..< codeEndIndex)

        let expectedBitmaskSize = (codeLength + 7) / 8

        guard expectedBitmaskSize == slice.endIndex - codeEndIndex else {
            throw Error.invalidDataLength
        }

        bitmask = Slice(base: blob, bounds: codeEndIndex ..< slice.endIndex)
    }

    public static func skipOffset<D>(start: UInt, bitmask: D) -> UInt? where D: Collection, D.Element == UInt8, D.Index == Int, D: ContiguousBytes {
        let start = start + 1
        let beginIndex = Int(start / 8)
        guard beginIndex < bitmask.endIndex else {
            return nil
        }

        var value: UInt32 = 0
        if (beginIndex + 4) < bitmask.endIndex { // if enough bytes
            value = bitmask.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: beginIndex, as: UInt32.self) }
        } else {
            let byte1 = UInt32(bitmask[beginIndex])
            let byte2 = UInt32(bitmask[safe: beginIndex + 1] ?? 0)
            let byte3 = UInt32(bitmask[safe: beginIndex + 2] ?? 0)
            let byte4 = UInt32(bitmask[safe: beginIndex + 3] ?? 0)
            value = byte1 | (byte2 << 8) | (byte3 << 16) | (byte4 << 24)
        }

        let offsetBits = start % 8

        let idx = min(UInt((value >> offsetBits).trailingZeroBitCount), Constants.maxInstructionLength)

        return idx
    }

    public func skip(start: UInt) -> UInt? {
        if let val = ProgramCode.skipOffset(start: start, bitmask: bitmask) {
            val + start + 1
        } else {
            nil
        }
    }
}

extension ProgramCode: Equatable {
    public static func == (lhs: ProgramCode, rhs: ProgramCode) -> Bool {
        lhs.blob == rhs.blob
    }
}
