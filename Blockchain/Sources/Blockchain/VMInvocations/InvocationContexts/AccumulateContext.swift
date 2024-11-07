import Foundation
import PolkaVM
import TracingUtils

private let logger = Logger(label: "AccumulateContext")

public class AccumulateContext: InvocationContext {
    public typealias ContextType = (
        x: AccumlateResultContext,
        y: AccumlateResultContext, // only set in checkpoint host-call
        timeslot: TimeslotIndex
    )

    public var config: ProtocolConfigRef
    public var context: ContextType

    public init(context: inout ContextType, config: ProtocolConfigRef) {
        self.config = config
        self.context = context
    }

    public func dispatch(index: UInt32, state: VMState) async -> ExecOutcome {
        logger.debug("dispatching host-call: \(index)")

        switch UInt8(index) {
        case Read.identifier:
            return await Read(serviceIndex: context.x.serviceIndex, accounts: context.x.serviceAccounts)
                .call(config: config, state: state)
        case Write.identifier:
            return await Write(serviceIndex: context.x.serviceIndex, accounts: &context.x.serviceAccounts)
                .call(config: config, state: state)
        case Lookup.identifier:
            return await Lookup(serviceIndex: context.x.serviceIndex, accounts: context.x.serviceAccounts)
                .call(config: config, state: state)
        case GasFn.identifier:
            return await GasFn().call(config: config, state: state)
        case Info.identifier:
            return await Info(serviceIndex: context.x.serviceIndex, accounts: context.x.serviceAccounts)
                .call(config: config, state: state)
        case Empower.identifier:
            return await Empower(x: &context.x).call(config: config, state: state)
        case Assign.identifier:
            return await Assign(x: &context.x).call(config: config, state: state)
        case Designate.identifier:
            return await Designate(x: &context.x).call(config: config, state: state)
        case Checkpoint.identifier:
            return await Checkpoint(x: context.x, y: &context.y).call(config: config, state: state)
        case New.identifier:
            return await New(x: &context.x).call(config: config, state: state)
        case Upgrade.identifier:
            return await Upgrade(x: &context.x)
                .call(config: config, state: state)
        case Transfer.identifier:
            return await Transfer(x: &context.x)
                .call(config: config, state: state)
        case Quit.identifier:
            return await Quit(x: &context.x)
                .call(config: config, state: state)
        case Solicit.identifier:
            return await Solicit(x: &context.x, timeslot: context.timeslot).call(config: config, state: state)
        case Forget.identifier:
            return await Forget(x: &context.x, timeslot: context.timeslot).call(config: config, state: state)
        default:
            state.consumeGas(Gas(10))
            state.writeRegister(Registers.Index(raw: 0), HostCallResultCode.WHAT.rawValue)
            return .continued
        }
    }

    // a check function to find the first such index in this sequence which does not already represent a service
    public static func check(i: ServiceIndex, serviceAccounts: [ServiceIndex: ServiceAccount]) -> ServiceIndex {
        if serviceAccounts[i] == nil {
            return i
        }

        return check(i: (i - 255) & (serviceIndexModValue - 1) + 256, serviceAccounts: serviceAccounts)
    }
}
