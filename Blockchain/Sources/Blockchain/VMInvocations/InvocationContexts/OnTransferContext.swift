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
        do {
            switch UInt8(index) {
            case Lookup.identifier:
                try Lookup.call(state: state, input: (context.account, context.index, context.accounts))
            case Read.identifier:
                try Read.call(state: state, input: (context.account, context.index, context.accounts))
            case Write.identifier:
                context.account = try Write.call(state: state, input: (config, context.account, context.index))
            case GasFn.identifier:
                try GasFn.call(state: state, input: ())
            case Info.identifier:
                try Info.call(state: state, input: (config, context.account, context.index, context.accounts, [:]))
            default:
                state.consumeGas(10)
                state.writeRegister(Registers.Index(raw: 0), HostCallResultCode.WHAT.rawValue)
            }
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
}
