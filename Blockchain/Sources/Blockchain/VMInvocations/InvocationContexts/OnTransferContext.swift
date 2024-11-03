import Foundation
import PolkaVM
import TracingUtils

private let logger = Logger(label: "OnTransferContext")

public class OnTransferContext: InvocationContext {
    public typealias ContextType = (
        account: ServiceAccount,
        index: ServiceIndex,
        accounts: [ServiceIndex: ServiceAccount]
    )

    public var config: ProtocolConfigRef
    public var context: ContextType

    public init(context: ContextType, config: ProtocolConfigRef) {
        self.config = config
        self.context = context
    }

    public func dispatch(index: UInt32, state: VMState) -> ExecOutcome {
        logger.debug("dispatching host-call: \(index)")
        switch UInt8(index) {
        case Lookup.identifier:
            return Lookup(account: context.account, serviceIndex: context.index, accounts: context.accounts)
                .call(config: config, state: state)
        case Read.identifier:
            return Read(account: context.account, serviceIndex: context.index, accounts: context.accounts)
                .call(config: config, state: state)
        case Write.identifier:
            return Write(account: &context.account, serviceIndex: context.index)
                .call(config: config, state: state)
        case GasFn.identifier:
            return GasFn().call(config: config, state: state)
        case Info.identifier:
            return Info(serviceIndex: context.index, accounts: context.accounts)
                .call(config: config, state: state)
        default:
            state.consumeGas(Gas(10))
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.WHAT.rawValue)
            return .continued
        }
    }
}
