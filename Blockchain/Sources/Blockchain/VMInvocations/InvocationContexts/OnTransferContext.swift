import Foundation
import PolkaVM
import TracingUtils

private let logger = Logger(label: "OnTransferContext")

public class OnTransferContext: InvocationContext {
    public class OnTransferContextType {
        var index: ServiceIndex
        var accounts: ServiceAccountsMutRef

        init(serviceIndex: ServiceIndex, accounts: ServiceAccountsMutRef) {
            index = serviceIndex
            self.accounts = accounts
        }
    }

    public typealias ContextType = OnTransferContextType

    public let config: ProtocolConfigRef
    public var context: ContextType

    public init(context: ContextType, config: ProtocolConfigRef) {
        self.config = config
        self.context = context
    }

    public func dispatch(index: UInt32, state: VMState) async -> ExecOutcome {
        logger.debug("dispatching host-call: \(index)")
        switch UInt8(index) {
        case Lookup.identifier:
            return await Lookup(serviceIndex: context.index, accounts: context.accounts.toRef())
                .call(config: config, state: state)
        case Read.identifier:
            return await Read(serviceIndex: context.index, accounts: context.accounts.toRef())
                .call(config: config, state: state)
        case Write.identifier:
            return await Write(serviceIndex: context.index, accounts: context.accounts)
                .call(config: config, state: state)
        case GasFn.identifier:
            return await GasFn().call(config: config, state: state)
        case Info.identifier:
            return await Info(serviceIndex: context.index, accounts: context.accounts.toRef())
                .call(config: config, state: state)
        case Log.identifier:
            return await Log(service: index).call(config: config, state: state)
        default:
            state.consumeGas(Gas(10))
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.WHAT.rawValue)
            return .continued
        }
    }
}
