import PolkaVM
import TracingUtils

private let logger = Logger(label: "HostCall")

public protocol HostCall {
    static var identifier: UInt8 { get }

    func gasCost() -> Gas
    func _callImpl(config: ProtocolConfigRef, state: VMState) throws
}

extension HostCall {
    public func call(config: ProtocolConfigRef, state: VMState) -> ExecOutcome {
        guard hasEnoughGas(state: state) else {
            logger.debug("not enough gas")
            return .exit(.outOfGas)
        }
        state.consumeGas(gasCost())
        logger.debug("consumed \(gasCost()) gas")

        do {
            try _callImpl(config: config, state: state)
            return .continued
        } catch let e as Memory.Error {
            logger.error("invocation memory error: \(e)")
            return .exit(.pageFault(e.address))
        } catch let e as VMInvocationsError {
            logger.error("invocation dispatch error: \(e)")
            return .exit(.panic(.trap))
        } catch let e {
            logger.error("invocation unknown error: \(e)")
            return .exit(.panic(.trap))
        }
    }

    // TODO: host-calls will have different gas costs later on
    public func gasCost() -> UInt64 {
        10
    }

    func hasEnoughGas(state: VMState) -> Bool {
        state.getGas() >= gasCost()
    }
}
