import Foundation
import PolkaVM
import TracingUtils

private let logger = Logger(label: "OnTransferContext")

public class OnTransferContext: InvocationContext {
    public typealias ContextType = (ServiceAccount, ServiceIndex, [ServiceIndex: ServiceAccount])

    public var context: ContextType

    public init(context: ContextType) {
        self.context = context
    }

    public func dispatch(index: UInt32, state: VMState) -> ExecOutcome {
        do {
            if index == Lookup.identifier {
                try Lookup.call(state: state, input: (context.0, context.1, context.2))
            } else if index == Read.identifier {
                try Read.call(state: state, input: (context.0, context.1, context.2))
            } else if index == Write.identifier {
                context.0 = try Write.call(state: state, input: (context.0, context.1, context.2))
            } else if index == GasFn.identifier {
                try GasFn.call(state: state, input: ())
            } else if index == Info.identifier {
                try Info.call(state: state, input: (context.0, context.1, context.2))
            } else {
                state.consumeGas(10)
                state.writeRegister(Registers.Index(raw: 0), HostCallResultCode.WHAT.rawValue)
            }
            return .continued
        } catch let e as VMInvocationsError {
            switch e {
            case let .pageFault(addr):
                return .exit(.pageFault(addr))
            default:
                logger.error("OnTransfer invocation dispatch error: \(e)")
                return .exit(.panic(.trap))
            }
        } catch let e {
            logger.error("OnTransfer invocation unknown error: \(e)")
            return .exit(.panic(.trap))
        }
    }
}
