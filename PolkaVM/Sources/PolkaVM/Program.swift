import Foundation
import Utils

public class Program {
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
}

extension Program: Equatable {
    public static func == (lhs: Program, rhs: Program) -> Bool {
        lhs.blob == rhs.blob
    }
}
