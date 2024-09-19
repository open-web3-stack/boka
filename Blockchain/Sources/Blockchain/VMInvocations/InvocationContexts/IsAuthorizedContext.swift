import Foundation
import PolkaVM
import TracingUtils

private let logger = Logger(label: "IsAuthorizedContext")

public class IsAuthorizedContext: InvocationContext {
    public typealias ContextType = Void

    public var context: ContextType = ()

    public init() {}

    public func dispatch(index: UInt32, state: VMState) -> ExecOutcome {
        do {
            if index == GasFn.identifier {
                try GasFn.call(state: state, input: ())
            } else {
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
