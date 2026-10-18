import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "Engine")

public class Engine {
    let config: PvmConfig
    let invocationContext: (any InvocationContext)?
    private var stepCounter: Int = 0
    private let enableStepLogging: Bool

    public init(config: PvmConfig, invocationContext: (any InvocationContext)? = nil, enableStepLogging: Bool = false) {
        self.config = config
        self.invocationContext = invocationContext
        self.enableStepLogging = enableStepLogging
    }

    public func execute(state: VMStateInterpreter) async -> ExitReason {
        guard (try? state.program.validate(pc: state.pc)) != nil else {
            return .panic(.invalidInstructionIndex)
        }
        let context = ExecutionContext(state: state, config: config)
        while true {
            if case let .exit(reason) = step(program: state.program, state: state, context: context) {
                switch reason {
                case let .hostCall(callIndex):
                    if case let .exit(hostExitReason) = await hostCall(state: state, callIndex: callIndex) {
                        return hostExitReason
                    }
                default:
                    return reason
                }
            }
        }
    }

    public func execute(state: any VMState) async -> ExitReason {
        guard (try? state.program.validate(pc: state.pc)) != nil else {
            return .panic(.invalidInstructionIndex)
        }
        let context = ExecutionContext(state: state, config: config)
        while true {
            if case let .exit(reason) = step(program: state.program, context: context) {
                switch reason {
                case let .hostCall(callIndex):
                    if case let .exit(hostExitReason) = await hostCall(state: state, callIndex: callIndex) {
                        return hostExitReason
                    }
                default:
                    return reason
                }
            }
        }
    }

    func hostCall(state: any VMState, callIndex: UInt32) async -> ExecOutcome {
        guard let invocationContext else {
            return .exit(.hostCall(callIndex))
        }

        let result = await invocationContext.dispatch(index: callIndex, state: state)
        switch result {
        case let .exit(reason):
            switch reason {
            case let .hostCall(callIndexInner):
                return await hostCall(state: state, callIndex: callIndexInner)
            default:
                return .exit(reason)
            }
        case .continued:
            let pc = state.pc
            let skip = state.program.skip(pc)
            state.increasePC(skip + 1)
            return .continued
        }
    }

    func step(program: ProgramCode, state: VMStateInterpreter, context: ExecutionContext) -> ExecOutcome {
        let pc = state.pc
        guard let inst = program.getInstructionForExecution(pc: pc) else {
            return .exit(.panic(.invalidInstructionIndex))
        }
        let skip = program.skip(pc)

        if !state.blockGasCharged {
            let cost = program.getBlockGasCosts(pc: pc)
            guard state.getGas() >= GasInt(cost) else {
                return .exit(.outOfGas)
            }
            state.consumeGas(cost)
            state.blockGasCharged = true
        }

        let result = inst.execute(context: context, skip: skip)

        #if DEBUG
            if enableStepLogging {
                logStep(instruction: inst, context: context)
            }
        #endif

        return result
    }

    func step(program: ProgramCode, context: ExecutionContext) -> ExecOutcome {
        let pc = context.state.pc
        guard let inst = program.getInstructionForExecution(pc: pc) else {
            return .exit(.panic(.invalidInstructionIndex))
        }
        let skip = program.skip(pc)

        if !context.state.blockGasCharged {
            let cost = program.getBlockGasCosts(pc: pc)
            guard context.state.getGas() >= GasInt(cost) else {
                return .exit(.outOfGas)
            }
            context.state.consumeGas(cost)
            context.state.blockGasCharged = true
        }

        let result = inst.execute(context: context, skip: skip)

        #if DEBUG
            if enableStepLogging {
                logStep(instruction: inst, context: context)
            }
        #endif

        return result
    }

    private func logStep(instruction: any Instruction, context: ExecutionContext) {
        let gas = context.state.getGas()
        let regArray = (0 ..< 13).map { context.state.readRegister(Registers.Index(raw: $0)) as UInt64 }
        let instructionName = getInstructionName(instruction)

        logger.trace("\(instructionName) \(stepCounter) \(context.state.pc) Gas: \(gas) Registers: \(regArray)")

        stepCounter += 1
    }

    private func getInstructionName(_ inst: any Instruction) -> String {
        let typeName = String(describing: type(of: inst))
        return typeName.replacingOccurrences(of: "Instructions::", with: "")
    }
}
