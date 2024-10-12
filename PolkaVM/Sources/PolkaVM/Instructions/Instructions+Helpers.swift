import Foundation

extension Instructions {
    enum Constants {
        static let djumpHaltAddress: UInt32 = 0xFFFF_0000
    }

    static func decodeImmediate(_ data: Data) -> UInt32 {
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
        // and then convert back to UInt32
        return UInt32(bitPattern: Int32(bitPattern: value << shift) >> shift)
    }

    static func decodeImmediate2(_ data: Data, divideBy: UInt8 = 1, minus: Int = 1) throws -> (UInt32, UInt32) {
        let lX1 = try Int((data.at(relative: 0) / divideBy) & 0b111)
        let lX = min(4, lX1)
        let lY = min(4, max(0, data.count - Int(lX) - minus))

        let vX = try decodeImmediate(data.at(relative: 1 ..< 1 + lX))
        let vY = try decodeImmediate(data.at(relative: (1 + lX) ..< (1 + lX + lY)))
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
