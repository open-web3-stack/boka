import Foundation

protocol Branch: Instruction {
    var offset: UInt32 { get }
    func condition(state: VMState) -> Bool
}

extension Branch {
    public func _executeImpl(context _: ExecutionContext) throws -> ExecOutcome { .continued }

    public func updatePC(context: ExecutionContext, skip: UInt32) -> ExecOutcome {
        let condition = condition(state: context.state)
        if !condition {
            context.state.increasePC(skip + 1)
        } else if !Instructions.isBranchValid(context: context, offset: offset) {
            return .exit(.panic(.invalidBranch))
        } else {
            context.state.increasePC(offset)
        }
        return .continued
    }
}

// for branch in A.5.7
protocol BranchInstructionBase<Compare>: Branch {
    associatedtype Compare: BranchCompare

    var register: Registers.Index { get set }
    var value: UInt32 { get set }
    var offset: UInt32 { get set }
}

extension BranchInstructionBase {
    public static func parse(data: Data) throws -> (Registers.Index, UInt32, UInt32) {
        let register = try Registers.Index(ra: data.at(relative: 0))
        let (value, offset) = try Instructions.decodeImmediate2(data, divideBy: 16)
        return (register, value, offset)
    }

    public func condition(state: VMState) -> Bool {
        let regVal = state.readRegister(register)
        return Compare.compare(a: regVal, b: value)
    }
}

// for branch in A.5.10
protocol BranchInstructionBase2<Compare>: Branch {
    associatedtype Compare: BranchCompare

    var r1: Registers.Index { get set }
    var r2: Registers.Index { get set }
    var offset: UInt32 { get set }
}

extension BranchInstructionBase2 {
    public static func parse(data: Data) throws -> (Registers.Index, Registers.Index, UInt32) {
        let offset = try Instructions.decodeImmediate(data.at(relative: 1...))
        let r1 = try Registers.Index(ra: data.at(relative: 0))
        let r2 = try Registers.Index(rb: data.at(relative: 0))
        return (r1, r2, offset)
    }

    public func condition(state: VMState) -> Bool {
        let (r1Val, r2Val) = state.readRegister(r1, r2)
        return Compare.compare(a: r1Val, b: r2Val)
    }
}
