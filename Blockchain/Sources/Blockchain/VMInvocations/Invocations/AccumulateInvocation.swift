import Codec
import Foundation
import PolkaVM
import Utils

extension AccumulateFunction {
    public func invoke(
        config: ProtocolConfigRef,
        accounts: inout some ServiceAccounts,
        state: AccumulateState,
        serviceIndex: ServiceIndex,
        gas: Gas,
        arguments: [AccumulateArguments],
        initialIndex: ServiceIndex,
        timeslot: TimeslotIndex
    ) async throws -> (state: AccumulateState, transfers: [DeferredTransfers], result: Data32?, gas: Gas) {
        guard let accumulatingAccountDetails = try await accounts.get(serviceAccount: serviceIndex) else {
            return (state, [], nil, Gas(0))
        }

        let resultCtx = AccumlateResultContext(
            serviceAccounts: accounts,
            serviceIndex: serviceIndex,
            accumulateState: state,
            nextAccountIndex: AccumulateContext.check(
                i: initialIndex & (serviceIndexModValue - 1) + 256,
                serviceAccounts: [:]
            ),
            transfers: []
        )

        var contextContent = AccumulateContext.ContextType(
            x: resultCtx,
            y: resultCtx
        )
        let ctx = AccumulateContext(context: &contextContent, config: config, timeslot: timeslot)
        let argument = try JamEncoder.encode(timeslot) + JamEncoder.encode(serviceIndex) + JamEncoder.encode(arguments)

        let (exitReason, gas, output) = await invokePVM(
            config: config,
            blob: accumulatingAccountDetails.codeHash.data,
            pc: 5,
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
