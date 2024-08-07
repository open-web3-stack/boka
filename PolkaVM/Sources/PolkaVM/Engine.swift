import Foundation

public class Engine {
    public enum Constants {
        public static let exitAddress: UInt32 = 0xFFFF_0000
    }

    public init() {}

    public func execute(program: ProgramCode, state: VMState) -> ExitReason {
        while true {
            guard state.getGas() > 0 else {
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
            return .panic(.invalidInstruction)
        }
        let startIndex = program.code.startIndex + Int(pc)
        let endIndex = startIndex + 1 + Int(skip)
        let data = if endIndex <= program.code.endIndex {
            program.code[startIndex ..< endIndex]
        } else {
            program.code[startIndex ..< min(program.code.endIndex, endIndex)] + Data(repeating: 0, count: endIndex - program.code.endIndex)
        }
        guard let inst = InstructionTable.parse(data) else {
            return .panic(.invalidInstruction)
        }

        let res = inst.execute(state: state, skip: skip)

        if state.pc == Constants.exitAddress {
            // TODO: GP only defined this for `djump` but not `branch`
            // so need to confirm this is correct
            return .halt
        }

        return res
    }
}
