import Foundation
import TracingUtils

private let logger = Logger(label: "Engine")

public class Engine {
    let config: PvmConfig

    public init(config: PvmConfig) {
        self.config = config
    }

    public func execute(program: ProgramCode, state: VMState) -> ExitReason {
        let context = ExecutionContext(state: state, config: config)
        while true {
            guard state.getGas() > 0 else {
                return .outOfGas
            }
            if case let .exit(reason) = step(program: program, context: context) {
                return reason
            }
        }
    }

    public func step(program: ProgramCode, context: ExecutionContext) -> ExecOutcome {
        let pc = context.state.pc
        let skip = program.skip(pc)
        let startIndex = program.code.startIndex + Int(pc)
        let endIndex = startIndex + 1 + Int(skip)
        let data = if endIndex <= program.code.endIndex {
            program.code[startIndex ..< endIndex]
        } else {
            program.code[startIndex ..< min(program.code.endIndex, endIndex)] + Data(repeating: 0, count: endIndex - program.code.endIndex)
        }
        guard let inst = InstructionTable.parse(data) else {
            return .exit(.panic(.invalidInstruction))
        }

        logger.debug("executing \(inst)", metadata: ["skip": "\(skip)", "pc": "\(context.state.pc)"])

        return inst.execute(context: context, skip: skip)
    }
}
