import Foundation
import TracingUtils

private let logger = Logger(label: "Insts   ")

extension Instructions {
    enum Constants {
        static let djumpHaltAddress: UInt32 = 0xFFFF_0000
    }

    static func decodeImmediate<T: FixedWidthInteger>(_ data: Data) -> T {
        // The immediate value (as encoded in the code blob) can be at most 4 bytes
        let len = min(data.count, 4)
        if len == 0 {
            return 0
        }
        var value: UInt32 = 0
        for i in 0 ..< len {
            value = value | (UInt32(data[relative: i]) << (8 * i))
        }
        let shift = (4 - len) * 8
        // shift left so that the MSB is the sign bit
        // and then do signed shift right to fill the empty bits using the sign bit
        let signExtendedValue = Int32(bitPattern: value << shift) >> shift
        return T(truncatingIfNeeded: signExtendedValue)
    }

    static func decodeImmediate2<T: FixedWidthInteger, U: FixedWidthInteger>(
        _ data: Data,
        divideBy: UInt8 = 1,
        minus: Int = 1,
        startIdx: Int = 0
    ) throws -> (T, U) {
        let lX1 = try Int((data.at(relative: startIdx) / divideBy) & 0b111)
        let lX = min(4, lX1)
        let lY = min(4, max(0, data.count - Int(lX) - minus))

        let start = startIdx + 1
        let vX: T = decodeImmediate((try? data.at(relative: start ..< (start + lX))) ?? Data())
        let vY: U = decodeImmediate((try? data.at(relative: (start + lX) ..< (start + lX + lY))) ?? Data())
        return (vX, vY)
    }

    static func isBranchValid(context: ExecutionContext, offset: UInt32) -> Bool {
        context.state.program.basicBlockIndices.contains(context.state.pc &+ offset)
    }

    static func djump(context: ExecutionContext, target: UInt32) -> ExecOutcome {
        if target == Constants.djumpHaltAddress {
            return .exit(.halt)
        }

        let za = context.config.pvmDynamicAddressAlignmentFactor

        if target == 0 || target > context.state.program.jumpTable.count * za || Int(target) % za != 0 {
            return .exit(.panic(.invalidDynamicJump))
        }

        let entrySize = Int(context.state.program.jumpTableEntrySize)
        let start = ((Int(target) / za) - 1) * entrySize
        let end = start + entrySize
        let jumpTable = context.state.program.jumpTable

        logger.trace("djump start (\(start)) end (\(end))")

        guard jumpTable.count >= (end - start), jumpTable.startIndex + end <= jumpTable.endIndex else {
            return .exit(.panic(.invalidDynamicJump))
        }

        var targetAlignedData = jumpTable[relative: start ..< end]
        logger.trace("djump target data (\(targetAlignedData.map(\.self)))")

        var targetAligned: any UnsignedInteger

        switch entrySize {
        case 1:
            let u8: UInt8? = targetAlignedData.decode(length: entrySize)
            guard let u8 else {
                return .exit(.panic(.invalidDynamicJump))
            }
            targetAligned = u8
        case 2:
            let u16: UInt16? = targetAlignedData.decode(length: entrySize)
            guard let u16 else {
                return .exit(.panic(.invalidDynamicJump))
            }
            targetAligned = u16
        case 3:
            let u32: UInt32? = targetAlignedData.decode(length: entrySize)
            guard let u32 else {
                return .exit(.panic(.invalidDynamicJump))
            }
            targetAligned = u32
        case 4:
            let u32: UInt32? = targetAlignedData.decode(length: entrySize)
            guard let u32 else {
                return .exit(.panic(.invalidDynamicJump))
            }
            targetAligned = u32
        default:
            return .exit(.panic(.invalidDynamicJump))
        }

        logger.trace("djump target decoded (\(targetAligned))")

        guard context.state.program.basicBlockIndices.contains(UInt32(targetAligned)) else {
            return .exit(.panic(.invalidDynamicJump))
        }

        context.state.updatePC(UInt32(targetAligned))
        return .continued
    }

    static func deocdeRegisters(_ data: Data) throws -> (Registers.Index, Registers.Index) {
        let ra = try Registers.Index(r1: data.at(relative: 0))
        let rb = try Registers.Index(r2: data.at(relative: 0))
        return (ra, rb)
    }

    static func deocdeRegisters(_ data: Data) throws -> (Registers.Index, Registers.Index, Registers.Index) {
        let ra = try Registers.Index(r1: data.at(relative: 0))
        let rb = try Registers.Index(r2: data.at(relative: 0))
        let rd = try Registers.Index(r3: data.at(relative: 1))
        return (ra, rb, rd)
    }
}
