import Foundation

public protocol Instruction {
    static var opcode: UInt8 { get }

    init(data: Data) throws

    func gasCost() -> UInt64
    func updatePC(state: VMState, skip: UInt32)

    // protected method
    func _executeImpl(state: VMState) throws -> ExitReason?
}

extension Instruction {
    public func execute(state: VMState, skip: UInt32) -> ExitReason? {
        state.consumeGas(gasCost())
        do {
            let res = try _executeImpl(state: state)
            if res == nil {
                updatePC(state: state, skip: skip)
            }
            return res
        } catch let e as Memory.Error {
            return .pageFault(e.address)
        } catch {
            // other unknown errors
            // TODO: log details
            return .panic(.trap)
        }
    }

    public func gasCost() -> UInt64 {
        1
    }

    public func updatePC(state: VMState, skip: UInt32) {
        state.increasePC(skip + 1)
    }
}
