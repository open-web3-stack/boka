import Foundation

public protocol Instruction {
    static var opcode: UInt8 { get }

    init?(data: Data)

    func execute(state: VMState, skip: UInt32) -> ExitReason?
    func executeImpl(state: VMState) -> ExitReason?

    func gasCost() -> UInt64
    func updatePC(state: VMState, skip: UInt32)
}

extension Instruction {
    public func execute(state: VMState, skip: UInt32) -> ExitReason? {
        state.consumeGas(gasCost())
        let res = executeImpl(state: state)
        if res == nil {
            state.updatePC(state.pc + skip + 1)
        }
        return res
    }

    public func gasCost() -> UInt64 {
        1
    }

    public func updatePC(state: VMState, skip: UInt32) {
        state.increasePC(skip + 1)
    }
}
