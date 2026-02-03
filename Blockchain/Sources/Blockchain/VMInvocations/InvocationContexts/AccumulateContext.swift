import Foundation
import PolkaVM
import TracingUtils

private let logger = Logger(label: "AccumulateContext")

public final class AccumulateContext: InvocationContext {
    public class AccumulateContextType {
        var x: AccumulateResultContext
        var y: AccumulateResultContext // only set in checkpoint host-call

        init(x: AccumulateResultContext, y: AccumulateResultContext) {
            self.x = x
            self.y = y
        }
    }

    public typealias ContextType = AccumulateContextType

    public let config: ProtocolConfigRef
    public var context: ContextType

    // other info needed for dispatches
    public let timeslot: TimeslotIndex
    public let inputs: [AccumulationInput]

    public init(context: ContextType, config: ProtocolConfigRef, timeslot: TimeslotIndex, inputs: [AccumulationInput]) {
        self.config = config
        self.context = context
        self.timeslot = timeslot
        self.inputs = inputs
    }

    public func dispatch(index: UInt32, state: VMState) async -> ExecOutcome {
        switch UInt8(index) {
        case GasFn.identifier:
            return await GasFn().call(config: config, state: state)
        case Fetch.identifier:
            return await Fetch(entropy: context.x.state.entropy, inputs: inputs)
                .call(config: config, state: state)
        case Read.identifier:
            return await Read(serviceIndex: context.x.serviceIndex, accounts: context.x.state.accounts.toRef())
                .call(config: config, state: state)
        case Write.identifier:
            return await Write(serviceIndex: context.x.serviceIndex, accounts: context.x.state.accounts)
                .call(config: config, state: state)
        case Lookup.identifier:
            return await Lookup(serviceIndex: context.x.serviceIndex, accounts: context.x.state.accounts.toRef())
                .call(config: config, state: state)
        case Info.identifier:
            return await Info(serviceIndex: context.x.serviceIndex, accounts: context.x.state.accounts.toRef())
                .call(config: config, state: state)
        case Bless.identifier:
            return await Bless(x: context.x).call(config: config, state: state)
        case Assign.identifier:
            return await Assign(x: context.x).call(config: config, state: state)
        case Designate.identifier:
            return await Designate(x: context.x).call(config: config, state: state)
        case Checkpoint.identifier:
            return await Checkpoint(x: context.x, y: context.y).call(config: config, state: state)
        case New.identifier:
            return await New(x: context.x, timeslot: timeslot).call(config: config, state: state)
        case Upgrade.identifier:
            return await Upgrade(x: context.x).call(config: config, state: state)
        case Transfer.identifier:
            return await Transfer(x: context.x).call(config: config, state: state)
        case Eject.identifier:
            return await Eject(x: context.x, timeslot: timeslot).call(config: config, state: state)
        case Query.identifier:
            return await Query(x: context.x).call(config: config, state: state)
        case Solicit.identifier:
            return await Solicit(x: context.x, timeslot: timeslot).call(config: config, state: state)
        case Forget.identifier:
            return await Forget(x: context.x, timeslot: timeslot).call(config: config, state: state)
        case Yield.identifier:
            return await Yield(x: context.x).call(config: config, state: state)
        case Provide.identifier:
            return await Provide(x: context.x).call(config: config, state: state)
        case Log.identifier:
            return await Log(service: context.x.serviceIndex).call(config: config, state: state)
        default:
            state.consumeGas(Gas(10))
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.WHAT.rawValue)
            return .continued
        }
    }

    /// a check function to find the first such index in this sequence which does not already represent a service
    public static func check(
        i: ServiceIndex,
        accounts: ServiceAccountsRef,
        config: ProtocolConfigRef,
    ) async throws -> ServiceIndex {
        if try await accounts.value.get(serviceAccount: i) == nil {
            return i
        }

        let S = UInt32(config.value.minPublicServiceIndex)
        let left = i - S + 1
        let right = UInt32.max - S - 255
        return try await check(i: (left % right) + S, accounts: accounts, config: config)
    }
}
