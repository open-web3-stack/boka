public class Engine {
    public init() {}

    public func execute(program: ProgramCode, state: VMState) -> ExitReason {
        while true {
            guard state.gas > 0 else {
                return .outOfGas
            }
            if let exitReason = step(program: program, state: state) {
                return exitReason
            }
        }
    }

    public func step(program: ProgramCode, state: VMState) -> ExitReason? {
        let pc = state.pc
        guard let skip = program.skip(state.pc) else {
            return .halt(.invalidInstruction)
        }
        guard let inst = InstructionTable.parse(program.code[Int(pc) ..< Int(pc + 1 + skip)]) else {
            return .halt(.invalidInstruction)
        }

        return inst.execute(state: state, skip: skip)
    }
}
