import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "Engine")

public class Engine {
    let config: PvmConfig
    let invocationContext: (any InvocationContext)?

    public init(config: PvmConfig, invocationContext: (any InvocationContext)? = nil) {
        self.config = config
        self.invocationContext = invocationContext
    }

    public func execute(program: ProgramCode, state: VMState) -> ExitReason {
        let context = ExecutionContext(state: state, config: config)
        while true {
            guard state.getGas() > GasInt(0) else {
                return .outOfGas
            }
            if case let .exit(reason) = step(program: program, context: context) {
                switch reason {
                case let .hostCall(callIndex):
                    if case let .exit(hostExitReason) = hostCall(state: state, callIndex: callIndex) {
                        return hostExitReason
                    }
                case .halt:
                    state.updatePC(0)
                    return reason
                case .panic:
                    state.updatePC(0)
                    return reason
                default:
                    return reason
                }
            }
        }
    }

    func hostCall(state: VMState, callIndex: UInt32) -> ExecOutcome {
        guard let invocationContext else {
            return .exit(.panic(.trap))
        }

        let result = invocationContext.dispatch(index: callIndex, state: state)
        switch result {
        case let .exit(reason):
            switch reason {
            case let .pageFault(address):
                return .exit(.pageFault(address))
            case let .hostCall(callIndexInner):
                let pc = state.pc
                let skip = state.program.skip(pc)
                state.increasePC(skip + 1)
                return hostCall(state: state, callIndex: callIndexInner)
            default:
                return .exit(reason)
            }
        case .continued:
            return .continued
        }
    }

    func step(program: ProgramCode, context: ExecutionContext) -> ExecOutcome {
        let pc = context.state.pc
        let skip = program.skip(pc)
        let inst = program.getInstructionAt(pc: pc)

        guard let inst else {
            return .exit(.panic(.invalidInstructionIndex))
        }

        // TODO: check after GP specified the behavior
        if context.state.program.basicBlockIndices.contains(pc) {
            let blockGas = context.state.program.getBlockGasCosts(pc: pc)
            context.state.consumeGas(blockGas)
            logger.debug("consumed \(blockGas) gas for block at pc: \(pc)")
        }

        logger.debug("executing \(inst)", metadata: ["skip": "\(skip)", "pc": "\(context.state.pc)"])

        return inst.execute(context: context, skip: skip)
    }
}
