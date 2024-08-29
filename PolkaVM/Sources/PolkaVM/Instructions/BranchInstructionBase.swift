import Foundation

// for branch in A.5.7
protocol BranchInstructionBase<Compare>: Instruction {
    associatedtype Compare: BranchCompare

    var register: Registers.Index { get set }
    var value: UInt32 { get set }
    var offset: UInt32 { get set }

    func condition(state: VMState) -> Bool
}

extension BranchInstructionBase {
    public static func parse(data: Data) throws -> (Registers.Index, UInt32, UInt32) {
        let register = try Registers.Index(ra: data.at(relative: 0))
        let (value, offset) = try Instructions.decodeImmediate2(data, divideBy: 16)
        return (register, value, offset)
    }

    public func _executeImpl(context _: ExecutionContext) throws -> ExecOutcome { .continued }

    public func updatePC(context: ExecutionContext, skip: UInt32) -> ExecOutcome {
        guard Instructions.isBranchValid(context: context, offset: offset) else {
            return .exit(.panic(.invalidBranch))
        }
        if condition(state: context.state) {
            context.state.increasePC(offset)
        } else {
            context.state.increasePC(skip + 1)
        }
        return .continued
    }

    public func condition(state: VMState) -> Bool {
        let regVal = state.readRegister(register)
        return Compare.compare(a: regVal, b: value)
    }
}

// for branch in A.5.10
protocol BranchInstructionBase2<Compare>: Instruction {
    associatedtype Compare: BranchCompare

    var r1: Registers.Index { get set }
    var r2: Registers.Index { get set }
    var offset: UInt32 { get set }

    func condition(state: VMState) -> Bool
}

extension BranchInstructionBase2 {
    public static func parse(data: Data) throws -> (Registers.Index, Registers.Index, UInt32) {
        let offset = try Instructions.decodeImmediate(data.at(relative: 1...))
        let r1 = try Registers.Index(ra: data.at(relative: 0))
        let r2 = try Registers.Index(rb: data.at(relative: 0))
        return (r1, r2, offset)
    }

    public func _executeImpl(context _: ExecutionContext) throws -> ExecOutcome { .continued }

    public func updatePC(context: ExecutionContext, skip: UInt32) -> ExecOutcome {
        guard Instructions.isBranchValid(context: context, offset: offset) else {
            return .exit(.panic(.invalidBranch))
        }
        if condition(state: context.state) {
            context.state.increasePC(offset)
        } else {
            context.state.increasePC(skip + 1)
        }
        return .continued
    }

    public func condition(state: VMState) -> Bool {
        let r1Val = state.readRegister(r1)
        let r2Val = state.readRegister(r2)
        return Compare.compare(a: r1Val, b: r2Val)
    }
}
