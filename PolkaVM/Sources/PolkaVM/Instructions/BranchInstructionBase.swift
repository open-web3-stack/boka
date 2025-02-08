import Foundation
import TracingUtils

private let logger = Logger(label: "Branch  ")

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

// for branch in A.5.8
protocol BranchInstructionBase<Compare>: Branch {
    associatedtype Compare: BranchCompare

    var register: Registers.Index { get set }
    var value: UInt64 { get set }
    var offset: UInt32 { get set }
}

extension BranchInstructionBase {
    public static func parse(data: Data) throws -> (Registers.Index, UInt64, UInt32) {
        let register = try Registers.Index(r1: data.at(relative: 0))
        let (value, offset): (UInt64, UInt32) = try Instructions.decodeImmediate2(data, divideBy: 16)
        return (register, value, offset)
    }

    public func condition(state: VMState) -> Bool {
        let regVal: UInt64 = state.readRegister(register)
        logger.trace("🔀    \(Compare.self) a(\(regVal)) b(\(value)) => \(Compare.compare(a: regVal, b: value))")
        return Compare.compare(a: regVal, b: value)
    }
}

// for branch in A.5.11
protocol BranchInstructionBase2<Compare>: Branch {
    associatedtype Compare: BranchCompare

    var r1: Registers.Index { get set }
    var r2: Registers.Index { get set }
    var offset: UInt32 { get set }
}

extension BranchInstructionBase2 {
    public static func parse(data: Data) throws -> (Registers.Index, Registers.Index, UInt32) {
        let offset: UInt32 = try Instructions.decodeImmediate(data.at(relative: 1...))
        let r1 = try Registers.Index(r1: data.at(relative: 0))
        let r2 = try Registers.Index(r2: data.at(relative: 0))
        return (r1, r2, offset)
    }

    public func condition(state: VMState) -> Bool {
        let (r1Val, r2Val): (UInt64, UInt64) = (state.readRegister(r1), state.readRegister(r2))
        logger.trace("🔀    \(Compare.self) a(\(r1Val)) b(\(r2Val)) => \(Compare.compare(a: r1Val, b: r2Val))")
        return Compare.compare(a: r1Val, b: r2Val)
    }
}
