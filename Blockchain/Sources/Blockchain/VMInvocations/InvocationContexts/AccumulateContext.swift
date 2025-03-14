import Foundation
import PolkaVM
import TracingUtils

private let logger = Logger(label: "AccumulateContext")

public class AccumulateContext: InvocationContext {
    public class AccumulateContextType {
        var x: AccumlateResultContext
        var y: AccumlateResultContext // only set in checkpoint host-call

        init(x: AccumlateResultContext, y: AccumlateResultContext) {
            self.x = x
            self.y = y
        }
    }

    public typealias ContextType = AccumulateContextType

    public let config: ProtocolConfigRef
    public var context: ContextType
    public let timeslot: TimeslotIndex

    public init(context: ContextType, config: ProtocolConfigRef, timeslot: TimeslotIndex) {
        self.config = config
        self.context = context
        self.timeslot = timeslot
    }

    public func dispatch(index: UInt32, state: VMState) async -> ExecOutcome {
        switch UInt8(index) {
        case Read.identifier:
            return await Read(serviceIndex: context.x.serviceIndex, accounts: context.x.state.accounts.toRef())
                .call(config: config, state: state)
        case Write.identifier:
            return await Write(serviceIndex: context.x.serviceIndex, accounts: context.x.state.accounts)
                .call(config: config, state: state)
        case Lookup.identifier:
            return await Lookup(serviceIndex: context.x.serviceIndex, accounts: context.x.state.accounts.toRef())
                .call(config: config, state: state)
        case GasFn.identifier:
            return await GasFn().call(config: config, state: state)
        case Info.identifier:
            return await Info(serviceIndex: context.x.serviceIndex, accounts: context.x.state.accounts.toRef())
                .call(config: config, state: state)
        case Bless.identifier:
            return await Bless(x: context.x).call(config: config, state: state)
        case Assign.identifier:
            let res = await Assign(x: context.x).call(config: config, state: state)
            return res
        case Designate.identifier:
            return await Designate(x: context.x).call(config: config, state: state)
        case Checkpoint.identifier:
            return await Checkpoint(x: context.x, y: context.y).call(config: config, state: state)
        case New.identifier:
            return await New(x: context.x).call(config: config, state: state)
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
        case Log.identifier:
            return await Log(service: context.x.serviceIndex).call(config: config, state: state)
        default:
            state.consumeGas(Gas(10))
            state.writeRegister(Registers.Index(raw: 0), HostCallResultCode.WHAT.rawValue)
            return .continued
        }
    }

    // a check function to find the first such index in this sequence which does not already represent a service
    public static func check(
        i: ServiceIndex,
        accounts: ServiceAccountsRef
    ) async throws -> ServiceIndex {
        if try await accounts.value.get(serviceAccount: i) == nil {
            return i
        }

        return try await check(i: (i - 255) % serviceIndexModValue + 256, accounts: accounts)
    }
}
