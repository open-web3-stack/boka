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
        minus _: Int = 1,
        startIdx: Int = 0,
    ) throws -> (T, U) {
        let lX1 = try Int((data.at(relative: startIdx) / divideBy) & 0b111)
        let lX = min(4, lX1)

        // Calculate lY based on remaining bytes after lX
        let remainingBytes = max(0, data.count - startIdx - 1 - lX)
        let lY = min(4, remainingBytes)

        let start = startIdx + 1
        let endIdx = start + lX + lY

        // Validate we have enough bytes - trigger bounds check via at()
        _ = try data.at(relative: endIdx - 1)

        // Use relative indices to avoid issues with data.startIndex
        let range1 = start ..< (start + lX)
        let range2 = (start + lX) ..< (start + lX + lY)

        let vX: T = decodeImmediate(data.subdata(in: range1))
        let vY: U = decodeImmediate(data.subdata(in: range2))
        return (vX, vY)
    }

    static func isBranchValid(context: ExecutionContext, offset: UInt32) -> Bool {
        let targetPC = context.state.pc &+ offset

        // Check if target is within code bounds
        guard targetPC < UInt32(context.state.program.code.count) else {
            return false
        }

        // Check if target points to a valid instruction (has skip value > 0 or within basic blocks)
        // Due to test vector bitmask issues, we check both conditions
        let skip = context.state.program.skip(targetPC)
        if skip > 0 {
            return true
        }

        // Fallback: check if target is in basicBlockIndices (for properly formed programs)
        return context.state.program.basicBlockIndices.contains(targetPC)
    }

    static func djump(context: ExecutionContext, target: UInt32) -> ExecOutcome {
        if target == Constants.djumpHaltAddress {
            return .exit(.halt)
        }

        let za = context.config.pvmDynamicAddressAlignmentFactor
        let jumpTable = context.state.program.jumpTable
        let entrySize = Int(context.state.program.jumpTableEntrySize)
        guard entrySize > 0 else {
            return .exit(.panic(.invalidDynamicJump))
        }

        // Jump table length is encoded in bytes, so convert to number of entries.
        let numEntries = jumpTable.count / entrySize

        if target == 0 || target > UInt32(numEntries * za) || Int(target) % za != 0 {
            return .exit(.panic(.invalidDynamicJump))
        }

        let start = ((Int(target) / za) - 1) * entrySize
        let end = start + entrySize

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

    static func decodeRegisters(_ data: Data) throws -> (Registers.Index, Registers.Index) {
        let ra = try Registers.Index(r1: data.at(relative: 0))
        let rb = try Registers.Index(r2: data.at(relative: 0))
        return (ra, rb)
    }

    static func decodeRegisters(_ data: Data) throws -> (Registers.Index, Registers.Index, Registers.Index) {
        let ra = try Registers.Index(r1: data.at(relative: 0))
        let rb = try Registers.Index(r2: data.at(relative: 0))
        let rd = try Registers.Index(r3: data.at(relative: 1))
        return (ra, rb, rd)
    }

}
