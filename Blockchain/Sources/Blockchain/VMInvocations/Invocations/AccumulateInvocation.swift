import Codec
import Foundation
import PolkaVM
import TracingUtils
import Utils

private let logger = Logger(label: "AccumulateInvocation")

public func accumulate(
    config: ProtocolConfigRef,
    state: AccumulateState,
    serviceIndex: ServiceIndex,
    gas: Gas,
    arguments: [AccumulationInput],
    timeslot: TimeslotIndex
) async throws -> AccumulationResult {
    logger.debug("accumulating service index: \(serviceIndex), gas: \(gas)")

    guard var accumulatingAccountDetails = try await state.accounts.value.get(serviceAccount: serviceIndex) else {
        logger.error("service account not found for service index: \(serviceIndex)")
        return .init(state: state, transfers: [], commitment: nil, gasUsed: Gas(0), provide: [])
    }

    let transfers = arguments.compactMap(\.deferredTransfers)
    let transferAmount = transfers.reduce(Balance(0)) { $0 + $1.amount }
    if transferAmount.value > 0 {
        accumulatingAccountDetails.balance += transferAmount
        logger.debug("updating balance for service \(serviceIndex): \(accumulatingAccountDetails.balance)")
        state.accounts.set(serviceAccount: serviceIndex, account: accumulatingAccountDetails)
    }

    guard let preimage = try await state.accounts.value.get(
        serviceAccount: serviceIndex,
        preimageHash: accumulatingAccountDetails.codeHash
    ) else {
        logger.error("code preimage not found for service index: \(serviceIndex)")
        return .init(state: state, transfers: [], commitment: nil, gasUsed: Gas(0), provide: [])
    }

    let codeBlob = try CodeAndMeta(data: preimage).codeBlob

    if codeBlob.count > config.value.maxServiceCodeSize {
        return .init(state: state, transfers: [], commitment: nil, gasUsed: Gas(0), provide: [])
    }

    let initialIndex = try Blake2b256.hash(JamEncoder.encode(UInt(serviceIndex), state.entropy, UInt(timeslot))).data.decode(UInt32.self)
    let S = UInt32(config.value.minPublicServiceIndex)
    let modValue = UInt32.max - S - 255
    let nextAccountIndex = try await AccumulateContext.check(
        i: (initialIndex % modValue) + S,
        accounts: state.accounts.toRef(),
        config: config
    )

    let contextContent = AccumulateContext.ContextType(
        x: AccumulateResultContext(
            serviceIndex: serviceIndex,
            state: state,
            nextAccountIndex: nextAccountIndex
        ),
        y: AccumulateResultContext(
            serviceIndex: serviceIndex,
            state: state.copy(),
            nextAccountIndex: nextAccountIndex
        )
    )
    let ctx = AccumulateContext(context: contextContent, config: config, timeslot: timeslot, inputs: arguments)
    let argumentData = try JamEncoder.encode(UInt(timeslot), UInt(serviceIndex), UInt(arguments.count))

    logger.info("=== Service \(serviceIndex): about to invokePVM with executionMode: \(executionMode), codeBlob size: \(codeBlob.count), gas: \(gas) ===")

    let (exitReason, gas, output) = await invokePVM(
        config: config,
        blob: codeBlob,
        pc: 5,
        gas: gas,
        argumentData: argumentData,
        ctx: ctx
    )

    logger.info("=== Service \(serviceIndex): exit reason: \(exitReason), remaining gas: \(gas), output: \(output?.toDebugHexString() ?? "nil") ===")

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
