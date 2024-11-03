import Codec
import Foundation
import PolkaVM
import Utils

extension AccumulateFunction {
    public func invoke(
        config: ProtocolConfigRef,
        state: AccumulateState,
        serviceIndex: ServiceIndex,
        gas: Gas,
        arguments: [AccumulateArguments],
        initialIndex: ServiceIndex,
        timeslot: TimeslotIndex
    ) throws -> (state: AccumulateState, transfers: [DeferredTransfers], result: Data32?, gas: Gas) {
        var serviceAccounts = state.serviceAccounts

        let defaultState = AccumulateState(
            serviceAccounts: [:],
            validatorQueue: state.validatorQueue,
            authorizationQueue: state.authorizationQueue,
            privilegedServices: state.privilegedServices
        )

        if serviceAccounts[serviceIndex]?.codeHash.data == nil {
            return (defaultState, [], nil, Gas(0))
        }

        guard let accumulatingAccount = serviceAccounts[serviceIndex] else {
            throw AccumulationError.invalidServiceIndex
        }

        serviceAccounts.removeValue(forKey: serviceIndex)

        let defaultCtx = try AccumlateResultContext(
            serviceAccounts: serviceAccounts,
            serviceIndex: serviceIndex,
            accumulateState: AccumulateState(
                serviceAccounts: [serviceIndex: accumulatingAccount],
                validatorQueue: state.validatorQueue,
                authorizationQueue: state.authorizationQueue,
                privilegedServices: state.privilegedServices
            ),
            nextAccountIndex: AccumulateContext.check(
                i: initialIndex & (serviceIndexModValue - 1) + 256,
                serviceAccounts: [serviceIndex: accumulatingAccount]
            ),
            transfers: []
        )

        let ctx = AccumulateContext(
            context: (
                x: defaultCtx,
                y: defaultCtx,
                timeslot: timeslot
            ),
            config: config
        )
        let argument = try JamEncoder.encode(arguments)

        let (exitReason, gas, output) = invokePVM(
            config: config,
            blob: serviceAccounts[serviceIndex]!.codeHash.data,
            pc: 10,
            gas: gas,
            argumentData: argument,
            ctx: ctx
        )

        return try collapse(exitReason: exitReason, output: output, context: ctx.context, gas: gas)
    }

    // collapse function C selects one of the two dimensions of context depending on whether the virtual
    // machine’s halt was regular or exceptional
    private func collapse(
        exitReason: ExitReason, output: Data?, context: AccumulateContext.ContextType, gas: Gas
    ) throws -> (state: AccumulateState, transfers: [DeferredTransfers], result: Data32?, gas: Gas) {
        switch exitReason {
        case .halt:
            if let output, let o = Data32(output) {
                (context.x.accumulateState, context.x.transfers, o, gas)
            } else {
                (context.x.accumulateState, context.x.transfers, nil, gas)
            }
        default:
            (context.y.accumulateState, context.y.transfers, nil, gas)
        }
    }
}
