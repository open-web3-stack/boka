import Foundation
import PolkaVM
import TracingUtils

private let logger = Logger(label: "IsAuthorizedContext")

public class IsAuthorizedContext: InvocationContext {
    public typealias ContextType = Void

    public var context: ContextType = ()
    public let config: ProtocolConfigRef

    public init(config: ProtocolConfigRef) {
        self.config = config
    }

    public func dispatch(index: UInt32, state: VMState) async -> ExecOutcome {
        if index == GasFn.identifier {
            return await GasFn().call(config: config, state: state)
        } else {
            state.consumeGas(Gas(10))
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.WHAT.rawValue)
            return .continued
        }
    }
}
