import Foundation

public class IsAuthorizedContext: HostCallContext {
    public typealias ContextType = Void

    public var context: ContextType = ()

    public init() {}

    public func dispatch(index: UInt32, state: VMState) -> ExecOutcome {
        if index == Gas.identifier {
            Gas.call(state: state, input: ())
        } else {
            state.consumeGas(10)
            state.writeRegister(Registers.Index(raw: 0), HostCallResultConstants.WHAT)
        }
        return .continued
    }
}
