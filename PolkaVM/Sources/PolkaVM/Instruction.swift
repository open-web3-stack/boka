import Foundation

public protocol Instruction {
    static var opcode: UInt8 { get }

    init(data: Data) throws

    func gasCost() -> UInt64
    func updatePC(context: ExecutionContext, skip: UInt32) -> ExecOutcome

    // protected method
    func _executeImpl(context: ExecutionContext) throws -> ExecOutcome
}

public class ExecutionContext {
    public let state: VMState
    public let config: PvmConfig

    public init(state: VMState, config: PvmConfig) {
        self.state = state
        self.config = config
    }
}

extension Instruction {
    public func execute(context: ExecutionContext, skip: UInt32) -> ExecOutcome {
        context.state.consumeGas(gasCost())
        do {
            let execRes = try _executeImpl(context: context)
            if case .exit = execRes {
                return execRes
            }
            return updatePC(context: context, skip: skip)
        } catch let e as Memory.Error {
            return .exit(.pageFault(e.address))
        } catch {
            // other unknown errors
            // TODO: log details
            return .exit(.panic(.trap))
        }
    }

    public func gasCost() -> UInt64 {
        1
    }

    public func updatePC(context: ExecutionContext, skip: UInt32) -> ExecOutcome {
        context.state.increasePC(skip + 1)
        return .continued
    }
}
