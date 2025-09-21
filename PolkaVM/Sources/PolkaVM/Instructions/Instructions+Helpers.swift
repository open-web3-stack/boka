import Foundation
import TracingUtils

private let logger = Logger(label: "Insts ")

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
        let vX: T = decodeImmediate(data.subdata(in: data.startIndex + start ..< data.startIndex + (start + lX)))
        let vY: U = decodeImmediate(data.subdata(in: data.startIndex + (start + lX) ..< data.startIndex + (start + lX + lY)))
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

        #if DEBUG
            logger.trace("djump start (\(start)) end (\(end))")
        #endif

        guard jumpTable.count >= (end - start), jumpTable.startIndex + end <= jumpTable.endIndex else {
            return .exit(.panic(.invalidDynamicJump))
        }

        var targetAlignedData = jumpTable.subdata(in: jumpTable.startIndex + start ..< jumpTable.startIndex + end)

        #if DEBUG
            logger.trace("djump target data (\(targetAlignedData.map(\.self)))")
        #endif

        let targetAligned: UInt32
        switch entrySize {
        case 1:
            targetAligned = UInt32(targetAlignedData.decodeUInt8())
        case 2:
            targetAligned = UInt32(targetAlignedData.decodeUInt16())
        case 3:
            targetAligned = targetAlignedData.decodeUInt24()
        case 4:
            targetAligned = targetAlignedData.decodeUInt32()
        default:
            guard let decoded: UInt32 = targetAlignedData.decode(length: entrySize) else {
                return .exit(.panic(.invalidDynamicJump))
            }
            targetAligned = decoded
        }

        #if DEBUG
            logger.trace("djump target decoded (\(targetAligned))")
        #endif

        guard context.state.program.basicBlockIndices.contains(targetAligned) else {
            return .exit(.panic(.invalidDynamicJump))
        }

        context.state.updatePC(targetAligned)
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
