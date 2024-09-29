import Foundation
import PolkaVM
import TracingUtils

private let logger = Logger(label: "AccumulateContext")

public class AccumulateContext: InvocationContext {
    public typealias ContextType = (
        x: AccumlateResultContext,
        y: AccumlateResultContext?, // only set in checkpoint function
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
                let newAccount = try Write.call(state: state, input: (config, context.x.account!, context.serviceIndex))
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
                try Empower.call(state: state, input: context.x)
            case Assign.identifier:
                try Assign.call(state: state, input: (config, context.x))
            case Designate.identifier:
                try Designate.call(state: state, input: (config, context.x))
            case Checkpoint.identifier:
                context.y = try Checkpoint.call(state: state, input: context.x)
            case New.identifier:
                try New.call(state: state, input: (config, context.x, context.accounts))
            case Upgrade.identifier:
                try Upgrade.call(state: state, input: (context.x, context.serviceIndex))
            case Transfer.identifier:
                try Transfer.call(state: state, input: (context.x, context.serviceIndex, context.accounts))
            case Quit.identifier:
                try Quit.call(state: state, input: (context.x, context.serviceIndex))
            case Solicit.identifier:
                try Solicit.call(state: state, input: (context.x, context.timeslot))
            case Forget.identifier:
                try Forget.call(state: state, input: (context.x, context.timeslot))
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

    // a check function to find the first such index in this sequence which does not already represent a service
    public static func check(i: ServiceIndex, serviceAccounts: [ServiceIndex: ServiceAccount]) throws -> ServiceIndex {
        var currentIndex = i
        let maxIter = serviceIndexModValue
        var iter = 0

        guard currentIndex >= 255 else {
            throw VMInvocationsError.checkIndexTooSmall
        }

        while serviceAccounts.keys.contains(currentIndex) {
            currentIndex = (currentIndex - 255) & (serviceIndexModValue - 1) + 256
            iter += 1

            if iter > maxIter {
                throw VMInvocationsError.checkMaxDepthLimit
            }
        }
        return currentIndex
    }
}
