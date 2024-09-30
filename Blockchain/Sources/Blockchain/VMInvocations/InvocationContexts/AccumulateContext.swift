import Foundation
import PolkaVM
import TracingUtils

private let logger = Logger(label: "AccumulateContext")

public class AccumulateContext: InvocationContext {
    public typealias ContextType = (
        x: AccumlateResultContext,
        y: AccumlateResultContext, // only set in checkpoint function
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
        logger.debug("dispatching host-call: \(index)")
        guard context.x.account != nil else {
            fatalError("context x.account is nil")
        }
        switch UInt8(index) {
        case Read.identifier:
            return Read(account: context.x.account!, serviceIndex: context.serviceIndex, accounts: context.accounts)
                .call(config: config, state: state)
        case Write.identifier:
            return Write(account: &context.x.account!, serviceIndex: context.serviceIndex)
                .call(config: config, state: state)
        case Lookup.identifier:
            return Lookup(account: context.x.account!, serviceIndex: context.serviceIndex, accounts: context.accounts)
                .call(config: config, state: state)
        case GasFn.identifier:
            return GasFn().call(config: config, state: state)
        case Info.identifier:
            return Info(
                account: context.x.account!,
                serviceIndex: context.serviceIndex,
                accounts: context.accounts,
                newAccounts: context.x.newAccounts
            )
            .call(config: config, state: state)
        case Empower.identifier:
            return Empower(x: &context.x).call(config: config, state: state)
        case Assign.identifier:
            return Assign(x: &context.x).call(config: config, state: state)
        case Designate.identifier:
            return Designate(x: &context.x).call(config: config, state: state)
        case Checkpoint.identifier:
            return Checkpoint(x: context.x, y: &context.y).call(config: config, state: state)
        case New.identifier:
            return New(x: &context.x, accounts: context.accounts).call(config: config, state: state)
        case Upgrade.identifier:
            return Upgrade(x: &context.x, serviceIndex: context.serviceIndex)
                .call(config: config, state: state)
        case Transfer.identifier:
            return Transfer(x: &context.x, serviceIndex: context.serviceIndex, accounts: context.accounts)
                .call(config: config, state: state)
        case Quit.identifier:
            return Quit(x: &context.x, serviceIndex: context.serviceIndex, accounts: context.accounts)
                .call(config: config, state: state)
        case Solicit.identifier:
            return Solicit(x: &context.x, timeslot: context.timeslot).call(config: config, state: state)
        case Forget.identifier:
            return Forget(x: &context.x, timeslot: context.timeslot).call(config: config, state: state)
        default:
            state.consumeGas(10)
            state.writeRegister(Registers.Index(raw: 0), HostCallResultCode.WHAT.rawValue)
            return .continued
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
