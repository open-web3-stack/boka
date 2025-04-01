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
) async throws -> AccumulationResult {
    logger.debug("accumulating service index: \(serviceIndex)")

    guard let accumulatingAccountDetails = try await state.accounts.value.get(serviceAccount: serviceIndex),
          let preimage = try await state.accounts.value.get(
              serviceAccount: serviceIndex,
              preimageHash: accumulatingAccountDetails.codeHash
          )
    else {
        return .init(state: state, transfers: [], commitment: nil, gasUsed: Gas(0))
    }

    let codeBlob = try CodeAndMeta(data: preimage).codeBlob

    let contextContent = try await AccumulateContext.ContextType(
        x: AccumlateResultContext(
            serviceIndex: serviceIndex,
            state: state,
            nextAccountIndex: AccumulateContext.check(
                i: initialIndex % serviceIndexModValue + 256,
                accounts: state.accounts.toRef()
            )
        ),
        y: AccumlateResultContext(
            serviceIndex: serviceIndex,
            state: state.copy(),
            nextAccountIndex: AccumulateContext.check(
                i: initialIndex % serviceIndexModValue + 256,
                accounts: state.accounts.toRef()
            )
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

    return try collapse(exitReason: exitReason, output: output, context: ctx.context, gas: gas)
}

// collapse function C selects one of the two dimensions of context depending on whether the virtual
// machine’s halt was regular or exceptional
private func collapse(
    exitReason: ExitReason, output: Data?, context: AccumulateContext.ContextType, gas: Gas
) throws -> AccumulationResult {
    switch exitReason {
    case .panic, .outOfGas:
        .init(state: context.y.state, transfers: context.y.transfers, commitment: context.y.yield, gasUsed: gas)
    default:
        if let output, let o = Data32(output) {
            .init(state: context.x.state, transfers: context.x.transfers, commitment: o, gasUsed: gas)

        } else {
            .init(state: context.x.state, transfers: context.x.transfers, commitment: context.x.yield, gasUsed: gas)
        }
    }
}
