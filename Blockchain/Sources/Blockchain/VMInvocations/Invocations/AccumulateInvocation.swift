import Codec
import Foundation
import PolkaVM
import TracingUtils
import Utils

private let logger = Logger(label: "accumulate")

public func accumulate(
    config: ProtocolConfigRef,
    state: AccumulateState,
    serviceIndex: ServiceIndex,
    gas: Gas,
    arguments: [AccumulateArguments],
    initialIndex: ServiceIndex,
    timeslot: TimeslotIndex
) async throws -> (state: AccumulateState, transfers: [DeferredTransfers], result: Data32?, gas: Gas) {
    logger.debug("accumulating service index: \(serviceIndex)")

    guard let accumulatingAccountDetails = try await state.accounts.value.get(serviceAccount: serviceIndex),
          let codeBlob = try await state.accounts.value.get(
              serviceAccount: serviceIndex,
              preimageHash: accumulatingAccountDetails.codeHash
          )
    else {
        return (state, [], nil, Gas(0))
    }

    let contextContent = try await AccumulateContext.ContextType(
        x: AccumlateResultContext(
            serviceIndex: serviceIndex,
            state: state,
            nextAccountIndex: AccumulateContext.check(
                i: initialIndex % serviceIndexModValue + 256,
                accounts: state.accounts.toRef()
            ),
            transfers: [],
            yield: nil
        ),
        y: AccumlateResultContext(
            serviceIndex: serviceIndex,
            state: state,
            nextAccountIndex: AccumulateContext.check(
                i: initialIndex % serviceIndexModValue + 256,
                accounts: state.accounts.toRef()
            ),
            transfers: [],
            yield: nil
        )
    )
    let ctx = AccumulateContext(context: contextContent, config: config, timeslot: timeslot)
    let argument = try JamEncoder.encode(timeslot, serviceIndex, arguments)

    let (exitReason, gas, output) = await invokePVM(
        config: config,
        blob: codeBlob,
        pc: 5,
        gas: gas,
        argumentData: argument,
        ctx: ctx
    )

    logger.debug("accumulate exit reason: \(exitReason)")
    logger.debug("accumulate output: \(output?.toDebugHexString() ?? "nil")")
    logger.debug("accumulate x.yield: \(ctx.context.x.yield?.toHexString() ?? "nil")")

    return try collapse(exitReason: exitReason, output: output, context: ctx.context, gas: gas)
}

// collapse function C selects one of the two dimensions of context depending on whether the virtual
// machine’s halt was regular or exceptional
private func collapse(
    exitReason: ExitReason, output: Data?, context: AccumulateContext.ContextType, gas: Gas
) throws -> (state: AccumulateState, transfers: [DeferredTransfers], result: Data32?, gas: Gas) {
    switch exitReason {
    case .panic, .outOfGas:
        (context.y.state, context.y.transfers, context.y.yield, gas)
    default:
        if let output, let o = Data32(output) {
            (context.x.state, context.x.transfers, o, gas)
        } else {
            (context.x.state, context.x.transfers, context.x.yield, gas)
        }
    }
}
