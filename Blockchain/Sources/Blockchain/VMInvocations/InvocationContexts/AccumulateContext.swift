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
        do {
            switch UInt8(index) {
            case Read.identifier:
                // x.account won't be nil here, already checked in AccumulateFunction.invoke
                try Read(serviceAccount: context.x.account!, serviceIndex: context.serviceIndex, serviceAccounts: context.accounts)
                    .call(config: config, state: state)
            case Write.identifier:
                try Write(serviceAccount: &context.x.account!, serviceIndex: context.serviceIndex)
                    .call(config: config, state: state)
            case Lookup.identifier:
                try Lookup(serviceAccount: context.x.account!, serviceIndex: context.serviceIndex, serviceAccounts: context.accounts)
                    .call(config: config, state: state)
            case GasFn.identifier:
                try GasFn().call(config: config, state: state)
            case Info.identifier:
                try Info(
                    serviceAccount: context.x.account!,
                    serviceIndex: context.serviceIndex,
                    serviceAccounts: context.accounts,
                    newServiceAccounts: context.x.newAccounts
                )
                .call(config: config, state: state)
            case Empower.identifier:
                try Empower(x: &context.x)
                    .call(config: config, state: state)
            case Assign.identifier:
                try Assign(x: &context.x)
                    .call(config: config, state: state)
            case Designate.identifier:
                try Designate(x: &context.x)
                    .call(config: config, state: state)
            case Checkpoint.identifier:
                try Checkpoint(x: context.x, y: &context.y)
                    .call(config: config, state: state)
            case New.identifier:
                try New(x: &context.x, accounts: context.accounts)
                    .call(config: config, state: state)
            case Upgrade.identifier:
                try Upgrade(x: &context.x, serviceIndex: context.serviceIndex)
                    .call(config: config, state: state)
            // case Transfer.identifier:
            //     try Transfer(x: context.x, serviceIndex: context.serviceIndex, serviceAccounts: context.accounts)
            //         .call(config: config, state: state)
            // case Quit.identifier:
            //     try Quit(x: context.x, serviceIndex: context.serviceIndex)
            //         .call(config: config, state: state)
            // case Solicit.identifier:
            //     try Solicit(x: context.x, timeslot: context.timeslot)
            //         .call(config: config, state: state)
            // case Forget.identifier:
            //     try Forget(x: context.x, timeslot: context.timeslot)
            //         .call(config: config, state: state)
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
