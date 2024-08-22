import Foundation

public protocol Instruction {
    static var opcode: UInt8 { get }

    init(data: Data) throws

    func gasCost() -> UInt64
    func updatePC(state: VMState, skip: UInt32) -> ExecOutcome

    // protected method
    func _executeImpl(state: VMState) throws -> ExecOutcome
}

extension Instruction {
    public func execute(state: VMState, skip: UInt32) -> ExecOutcome {
        state.consumeGas(gasCost())
        do {
            let execRes = try _executeImpl(state: state)
            if case .exit = execRes {
                return execRes
            }
            return updatePC(state: state, skip: skip)
        } catch let e as Memory.Error {
            return .exit(.pageFault(e.address))
        } catch {
            // other unknown errors
            // TODO: log details
            return .exit(.panic(.trap))
        }
    }

    public func gasCost() -> UInt64 {
        1
    }

    public func updatePC(state: VMState, skip: UInt32) -> ExecOutcome {
        state.increasePC(skip + 1)
        return .continued
    }
}
