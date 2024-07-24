public class Engine {
    public init() {}

    public func execute(program: ProgramCode, state: inout VMState) -> ExitReason {
        while true {
            guard state.gas > 0 else {
                return .outOfGas
            }
            if let exitReason = step(program: program, state: &state) {
                return exitReason
            }
        }
    }

    public func step(program _: ProgramCode, state _: inout VMState) -> ExitReason? {
        nil
    }
}
