import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "Instruction")

public protocol Instruction {
    static var opcode: UInt8 { get }

    init(data: Data) throws

    func gasCost() -> Gas
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
        do {
            let execRes = try _executeImpl(context: context)
            if case .exit = execRes {
                return execRes
            }
            logger.debug("execution success! updating pc...")
            return updatePC(context: context, skip: skip)
        } catch let e as Memory.Error {
            logger.debug("memory error: \(e)")
            return .exit(.pageFault(e.address))
        } catch let e {
            // other unknown errors
            logger.error("execution failed!", metadata: ["error": "\(e)"])
            return .exit(.panic(.trap))
        }
    }

    public func gasCost() -> Gas {
        Gas(1)
    }

    public func updatePC(context: ExecutionContext, skip: UInt32) -> ExecOutcome {
        context.state.increasePC(skip + 1)
        return .continued
    }
}
