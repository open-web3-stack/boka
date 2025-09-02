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

    public func execute(state: any VMState) async -> ExitReason {
        let context = ExecutionContext(state: state, config: config)
        while true {
            guard state.getGas() > GasInt(0) else {
                return .outOfGas
            }
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
            return .exit(.panic(.trap))
        }

        let result = await invocationContext.dispatch(index: callIndex, state: state)
        switch result {
        case let .exit(reason):
            switch reason {
            case let .pageFault(address):
                return .exit(.pageFault(address))
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

    func step(program: ProgramCode, context: ExecutionContext) -> ExecOutcome {
        let pc = context.state.pc
        let skip = program.skip(pc)

        let inst = program.getInstructionAt(pc: pc)
        guard let inst else {
            return .exit(.panic(.invalidInstructionIndex))
        }

        // consume gas per instruction
        context.state.consumeGas(inst.gasCost())

        // TODO: Enable basic block based gas consumption when GP specifies it
        // if context.state.program.basicBlockIndices.contains(pc) {
        //     let blockGas = context.state.program.getBlockGasCosts(pc: pc)
        //     context.state.consumeGas(blockGas)
        // }

        #if DEBUG
            if enableStepLogging {
                logStep(pc: pc, instruction: inst, context: context)
            }
        #endif

        return inst.execute(context: context, skip: skip)
    }

    private func logStep(pc: UInt32, instruction: any Instruction, context: ExecutionContext) {
        stepCounter += 1

        let gas = context.state.getGas()
        let regArray = (0 ..< 13).map { context.state.readRegister(Registers.Index(raw: $0)) as UInt64 }
        let instructionName = getInstructionName(instruction).padding(toLength: 20, withPad: " ", startingAt: 0)

        logger.trace("\(String(format: "%4d", stepCounter)): PC \(String(format: "%6d", pc)) \(instructionName) g=\(gas) reg=\(regArray)")
    }

    private func getInstructionName(_ inst: any Instruction) -> String {
        let typeName = String(describing: type(of: inst))
        let cleanName = typeName.replacingOccurrences(of: "Instructions.", with: "")
        return cleanName.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1_$2", options: .regularExpression).uppercased()
    }
}
