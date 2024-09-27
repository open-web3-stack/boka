import Foundation
import PolkaVM
import TracingUtils

private let logger = Logger(label: "AccumulateContext")

public class AccumulateContext: InvocationContext {
    public typealias ContextType = (
        x: AccumlateResultContext,
        y: AccumlateResultContext,
        serviceIndex: ServiceIndex,
        accounts: [ServiceIndex: ServiceAccount],
        timeslot: TimeslotIndex
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
            case Read.identifier:
                // x.account won't be nil here, already checked in AccumulateFunction.invoke
                try Read.call(state: state, input: (context.x.account!, context.serviceIndex, context.accounts))
            case Write.identifier:
                let newAccount = try Write.call(
                    state: state,
                    input: (config, context.x.account!, context.serviceIndex)
                )
                context.x.account = newAccount
            case Lookup.identifier:
                try Lookup.call(state: state, input: (context.x.account!, context.serviceIndex, context.accounts))
            case GasFn.identifier:
                try GasFn.call(state: state, input: ())
            case Info.identifier:
                try Info.call(
                    state: state,
                    input: (config, context.x.account!, context.serviceIndex, context.accounts, context.x.newAccounts)
                )
            case Empower.identifier:
                try Empower.call(state: state, input: (context.x, context.y))
            case Assign.identifier:
                try Assign.call(state: state, input: (context.x, context.y))
            case Designate.identifier:
                try Designate.call(state: state, input: (context.x, context.y))
            case Checkpoint.identifier:
                try Checkpoint.call(state: state, input: (context.x, context.y))
            case New.identifier:
                try New.call(state: state, input: (context.x, context.y))
            case Upgrade.identifier:
                try Upgrade.call(state: state, input: (context.x, context.y, context.serviceIndex))
            case Transfer.identifier:
                try Transfer.call(state: state, input: (context.x, context.y, context.serviceIndex, context.accounts))
            case Quit.identifier:
                try Quit.call(state: state, input: (context.x, context.y, context.serviceIndex))
            case Solicit.identifier:
                try Solicit.call(state: state, input: (context.x, context.y, context.timeslot))
            case Forget.identifier:
                try Forget.call(state: state, input: (context.x, context.y, context.timeslot))
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
