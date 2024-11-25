import Foundation

extension Instructions {
    enum Constants {
        static let djumpHaltAddress: UInt32 = 0xFFFF_0000
    }

    static func decodeImmediate<T: FixedWidthInteger>(_ data: Data) -> T {
        let maxLen = T.bitWidth / 8
        let len: Int = min(data.count, maxLen)
        if len == 0 {
            return 0
        }
        var value: UInt64 = 0
        for i in 0 ..< len {
            value = value | (UInt64(data[relative: i]) << (8 * i))
        }
        let shift = (maxLen - len) * 8
        // shift left so that the MSB is the sign bit
        // and then do signed shift right to fill the empty bits using the sign bit
        // and then convert back to UInt64
        return .init(truncatingIfNeeded: UInt64(bitPattern: Int64(bitPattern: value << shift) >> shift))
    }

    static func decodeImmediate2<T: FixedWidthInteger, U: FixedWidthInteger>(
        _ data: Data,
        divideBy: UInt8 = 1,
        minus: Int = 1
    ) throws -> (T, U) {
        let lX1 = try Int((data.at(relative: 0) / divideBy) & 0b111)
        let lX = min(T.bitWidth / 8, lX1)
        let lY = min(U.bitWidth / 8, max(0, data.count - Int(lX) - minus))

        let vX: T = try decodeImmediate(data.at(relative: 1 ..< 1 + lX))
        let vY: U = try decodeImmediate(data.at(relative: (1 + lX) ..< (1 + lX + lY)))
        return (vX, vY)
    }

    static func isBranchValid(context: ExecutionContext, offset: UInt32) -> Bool {
        context.state.program.basicBlockIndices.contains(context.state.pc &+ offset)
    }

    static func isDjumpValid(context: ExecutionContext, target a: UInt32, targetAligned: UInt32) -> Bool {
        let za = context.config.pvmDynamicAddressAlignmentFactor
        return !(a == 0 ||
            a > context.state.program.jumpTable.count * za ||
            Int(a) % za != 0 ||
            context.state.program.basicBlockIndices.contains(targetAligned))
    }

    static func djump(context: ExecutionContext, target: UInt32) -> ExecOutcome {
        if target == Constants.djumpHaltAddress {
            return .exit(.halt)
        }

        let entrySize = Int(context.state.program.jumpTableEntrySize)
        let start = ((Int(target) / context.config.pvmDynamicAddressAlignmentFactor) - 1) * entrySize
        let end = start + entrySize
        var targetAlignedData = context.state.program.jumpTable[relative: start ..< end]
        guard let targetAligned = targetAlignedData.decode() else {
            return .exit(.panic(.trap))
        }

        guard isDjumpValid(context: context, target: target, targetAligned: UInt32(truncatingIfNeeded: targetAligned)) else {
            return .exit(.panic(.invalidDynamicJump))
        }

        context.state.updatePC(UInt32(targetAligned))
        return .continued
    }

    static func deocdeRegisters(_ data: Data) throws -> (Registers.Index, Registers.Index) {
        let ra = try Registers.Index(ra: data.at(relative: 0))
        let rb = try Registers.Index(rb: data.at(relative: 0))
        return (ra, rb)
    }

    static func deocdeRegisters(_ data: Data) throws -> (Registers.Index, Registers.Index, Registers.Index) {
        let ra = try Registers.Index(ra: data.at(relative: 0))
        let rb = try Registers.Index(rb: data.at(relative: 0))
        let rd = try Registers.Index(rd: data.at(relative: 1))
        return (ra, rb, rd)
    }
}
