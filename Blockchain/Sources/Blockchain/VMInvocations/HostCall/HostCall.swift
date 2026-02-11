import PolkaVM
import TracingUtils
import Utils

private let logger = Logger(label: "HostCall ")

public protocol HostCall {
    static var identifier: UInt8 { get }

    func gasCost(state: VMState) -> Gas
    func _callImpl(config: ProtocolConfigRef, state: VMState) async throws
}

extension HostCall {
    public func call(config: ProtocolConfigRef, state: VMState) async -> ExecOutcome {
        logger.debug("===== host call: \(Self.self) =====")
        state.consumeGas(gasCost(state: state))
        logger.debug("consumed \(gasCost(state: state)) gas, \(state.getGas()) left")

        guard state.getGas() >= GasInt(0) else {
            logger.trace("not enough gas")
            return .exit(.outOfGas)
        }

        do {
            try await _callImpl(config: config, state: state)
            return .continued
        } catch let e as MemoryError {
            logger.trace("memory error: \(e)")
            return .exit(.pageFault(e.address))
        } catch VMInvocationsError.forceHalt {
            logger.trace("force halt")
            return .exit(.halt)
        } catch let e as VMInvocationsError {
            logger.trace("invocation error: \(e)")
            return .exit(.panic(.trap))
        } catch let e {
            logger.trace("unknown error: \(e)")
            return .exit(.panic(.trap))
        }
    }

    /// Calculate gas cost for host-call execution
    /// Note: Currently uses flat rate of 10 gas units for all host-calls.
    /// Future enhancement: Implement differentiated gas costs based on:
    /// - Host-call type (storage operations more expensive than queries)
    /// - Input data size
    /// - Computational complexity
    /// - Resource consumption (I/O, cryptography, etc.)
    public func gasCost(state _: VMState) -> Gas {
        Gas(10)
    }
}
