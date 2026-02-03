import Foundation
import PolkaVM
import TracingUtils

private let logger = Logger(label: "IsAuthorizedContext")

public final class IsAuthorizedContext: InvocationContext {
    public typealias ContextType = Void

    public var context: ContextType = ()
    public let config: ProtocolConfigRef

    /// other info needed for dispatches
    public let package: WorkPackage

    public init(config: ProtocolConfigRef, package: WorkPackage) {
        self.config = config
        self.package = package
    }

    public func dispatch(index: UInt32, state: VMState) async -> ExecOutcome {
        switch UInt8(index) {
        case GasFn.identifier:
            return await GasFn().call(config: config, state: state)
        case Fetch.identifier:
            return await Fetch(workPackage: package).call(config: config, state: state)
        case Log.identifier:
            return await Log().call(config: config, state: state)
        default:
            state.consumeGas(Gas(10))
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.WHAT.rawValue)
            return .continued
        }
    }
}
