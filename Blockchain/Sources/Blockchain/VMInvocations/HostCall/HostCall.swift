import PolkaVM
import TracingUtils

private let logger = Logger(label: "HostCall")

public protocol HostCall {
    static var identifier: UInt8 { get }

    func gasCost() -> Gas
    func _callImpl(config: ProtocolConfigRef, state: VMState) throws
}

extension HostCall {
    public func call(config: ProtocolConfigRef, state: VMState) throws {
        guard hasEnoughGas(state: state) else { return }
        state.consumeGas(gasCost())
        logger.debug("consumed \(gasCost()) gas")
        return try _callImpl(config: config, state: state)
    }

    // TODO: host-calls will have different gas costs later on
    public func gasCost() -> UInt64 {
        10
    }

    func hasEnoughGas(state: VMState) -> Bool {
        state.getGas() >= gasCost()
    }
}
