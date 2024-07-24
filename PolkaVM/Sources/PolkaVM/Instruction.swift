import Foundation

public protocol Instruction {
    static var opcode: UInt8 { get }

    init?(data: Data)

    func execute(state: inout VMState) -> ExitReason?
    func executeImpl(state: inout VMState) -> ExitReason?

    func gasCost() -> UInt64
}

extension Instruction {
    public func execute(state: inout VMState) -> ExitReason? {
        state.consumeGas(gasCost())
        return executeImpl(state: &state)
    }
}
