import Codec
import Foundation
import PolkaVM
import TracingUtils
import Utils

private let logger = Logger(label: "accumulate")

public func accumulate(
    config: ProtocolConfigRef,
    serviceAccounts: ServiceAccountsMutRef,
    accumulateState: AccumulateState,
    serviceIndex: ServiceIndex,
    gas: Gas,
    arguments: [AccumulateArguments],
    initialIndex: ServiceIndex,
    timeslot: TimeslotIndex
) async throws -> (state: AccumulateState, transfers: [DeferredTransfers], result: Data32?, gas: Gas) {
    logger.debug("accumulating service index: \(serviceIndex)")

    guard let accumulatingAccountDetails = try await serviceAccounts.value.get(serviceAccount: serviceIndex),
          let codeBlob = try await serviceAccounts.value.get(
              serviceAccount: serviceIndex,
              preimageHash: accumulatingAccountDetails.codeHash
          )
    else {
        return (accumulateState, [], nil, Gas(0))
    }

    let contextContent = AccumulateContext.ContextType(
        x: AccumlateResultContext(
            serviceAccounts: serviceAccounts,
            serviceIndex: serviceIndex,
            accumulateState: accumulateState,
            nextAccountIndex: AccumulateContext.check(
                i: initialIndex & (serviceIndexModValue - 1) + 256,
                serviceAccounts: [:]
            ),
            transfers: [],
            yield: nil
        ),
        y: AccumlateResultContext(
            serviceAccounts: serviceAccounts,
            serviceIndex: serviceIndex,
            accumulateState: accumulateState,
            nextAccountIndex: AccumulateContext.check(
                i: initialIndex & (serviceIndexModValue - 1) + 256,
                serviceAccounts: [:]
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

    // logger.debug("x accumulateState: \(ctx.context.x.accumulateState)")
    // logger.debug("y accumulateState: \(ctx.context.y.accumulateState)")

    return try collapse(exitReason: exitReason, output: output, context: ctx.context, gas: gas)
}

// collapse function C selects one of the two dimensions of context depending on whether the virtual
// machine’s halt was regular or exceptional
private func collapse(
    exitReason: ExitReason, output: Data?, context: AccumulateContext.ContextType, gas: Gas
) throws -> (state: AccumulateState, transfers: [DeferredTransfers], result: Data32?, gas: Gas) {
    switch exitReason {
    case .panic, .outOfGas:
        (context.y.accumulateState, context.y.transfers, context.y.yield, gas)
    default:
        if let output, let o = Data32(output) {
            (context.x.accumulateState, context.x.transfers, o, gas)
        } else {
            (context.x.accumulateState, context.x.transfers, context.x.yield, gas)
        }
    }
}
