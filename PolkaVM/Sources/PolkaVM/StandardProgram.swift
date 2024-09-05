import Foundation
import TracingUtils
import Utils

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

    public init(_ blob: Data) throws {
        var slice = Slice(base: blob, bounds: blob.startIndex ..< blob.endIndex)
        guard let oLen: UInt32 = slice.decode(length: 3) else { // TODO: o is auth output? check and rename these
            throw Error.invalidStandardProgram
        }
        guard let wLen: UInt32 = slice.decode(length: 3) else {
            throw Error.invalidStandardProgram
        }
        guard let z: UInt16 = slice.decode(length: 2) else {
            throw Error.invalidStandardProgram
        }
        guard let s: UInt32 = slice.decode(length: 3) else {
            throw Error.invalidStandardProgram
        }

        let oEndIdx = slice.startIndex + Int(oLen)
        guard oEndIdx <= slice.endIndex else {
            throw Error.invalidStandardProgram
        }
        let o = blob[slice.startIndex ..< oEndIdx]

        let wEndIdx = oEndIdx + Int(wLen)
        guard wEndIdx <= slice.endIndex else {
            throw Error.invalidStandardProgram
        }
        let w = blob[oEndIdx ..< wEndIdx]

        slice = slice.dropFirst(Int(oLen) + Int(wLen))

        guard let codeLength: UInt32 = slice.decode(length: 4), slice.startIndex + Int(codeLength) <= slice.endIndex else {
            throw Error.invalidStandardProgram
        }

        code = try ProgramCode(blob[relative: slice.startIndex ..< slice.startIndex + Int(codeLength)])
    }
}
