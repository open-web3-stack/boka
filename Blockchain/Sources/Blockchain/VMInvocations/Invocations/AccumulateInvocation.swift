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
    arguments: [OperandTuple],
    timeslot: TimeslotIndex
) async throws -> AccumulationResult {
    logger.debug("accumulating service index: \(serviceIndex)")

    guard let accumulatingAccountDetails = try await state.accounts.value.get(serviceAccount: serviceIndex),
          let preimage = try await state.accounts.value.get(
              serviceAccount: serviceIndex,
              preimageHash: accumulatingAccountDetails.codeHash
          )
    else {
        return .init(state: state, transfers: [], commitment: nil, gasUsed: Gas(0), provide: [])
    }

    let codeBlob = try CodeAndMeta(data: preimage).codeBlob

    if codeBlob.count > config.value.maxServiceCodeSize {
        return .init(state: state, transfers: [], commitment: nil, gasUsed: Gas(0), provide: [])
    }

    let initialIndex = try Blake2b256.hash(JamEncoder.encode(serviceIndex, state.entropy, timeslot)).data.decode(UInt32.self)
    let nextAccountIndex = try await AccumulateContext.check(
        i: initialIndex % serviceIndexModValue + 256,
        accounts: state.accounts.toRef()
    )

    let contextContent = AccumulateContext.ContextType(
        x: AccumlateResultContext(
            serviceIndex: serviceIndex,
            state: state,
            nextAccountIndex: nextAccountIndex
        ),
        y: AccumlateResultContext(
            serviceIndex: serviceIndex,
            state: state.copy(),
            nextAccountIndex: nextAccountIndex
        )
    )
    let ctx = AccumulateContext(context: contextContent, config: config, timeslot: timeslot, operands: arguments)
    let argument = try JamEncoder.encode(UInt(timeslot), UInt(serviceIndex), UInt(arguments.count))

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
        .init(
            state: context.y.state,
            transfers: context.y.transfers,
            commitment: context.y.yield,
            gasUsed: gas,
            provide: context.y.provide
        )
    default:
        if let output, let o = Data32(output) {
            .init(
                state: context.x.state,
                transfers: context.x.transfers,
                commitment: o,
                gasUsed: gas,
                provide: context.x.provide
            )

        } else {
            .init(
                state: context.x.state,
                transfers: context.x.transfers,
                commitment: context.x.yield,
                gasUsed: gas,
                provide: context.x.provide
            )
        }
    }
}
