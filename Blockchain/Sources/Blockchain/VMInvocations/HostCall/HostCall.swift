import PolkaVM
import TracingUtils

private let logger = Logger(label: "HostCall")

public protocol HostCall {
    static var identifier: UInt8 { get }

    func gasCost(state: VMState) -> Gas
    func _callImpl(config: ProtocolConfigRef, state: VMState) async throws
}

extension HostCall {
    public func call(config: ProtocolConfigRef, state: VMState) async -> ExecOutcome {
        guard hasEnoughGas(state: state) else {
            logger.debug("not enough gas")
            return .exit(.outOfGas)
        }
        state.consumeGas(gasCost(state: state))
        logger.debug("consumed \(gasCost(state: state)) gas")

        do {
            try await _callImpl(config: config, state: state)
            return .continued
        } catch let e as Memory.Error {
            logger.error("memory error: \(e)")
            return .exit(.pageFault(e.address))
        } catch VMInvocationsError.forceHalt {
            logger.debug("force halt")
            return .exit(.halt)
        } catch let e as VMInvocationsError {
            logger.error("invocation error: \(e)")
            return .exit(.panic(.trap))
        } catch let e {
            logger.error("unknown error: \(e)")
            return .exit(.panic(.trap))
        }
    }

    // TODO: host-calls will have different gas costs later on
    public func gasCost(state _: VMState) -> Gas {
        Gas(10)
    }

    func hasEnoughGas(state: VMState) -> Bool {
        Gas(state.getGas()) >= gasCost(state: state)
    }
}
