import Codec
import Foundation
import PolkaVM
import Utils

public func refine(
    config: ProtocolConfigRef,
    serviceAccounts: some ServiceAccounts,
    // Index of the work item to be refined
    workItemIndex: Int,
    // The work package
    workPackage: WorkPackage,
    // The core which is doing refine
    coreIndex: CoreIndex,
    // The output of the authorizer
    authorizerTrace: Data,
    // all work items's import segments
    importSegments: [[Data4104]],
    // Export segment offset
    exportSegmentOffset: UInt64,
) async throws -> (result: Result<Data, WorkResultError>, exports: [Data4104], gasUsed: Gas) {
    let workItem = workPackage.workItems[workItemIndex]
    let service = workItem.serviceIndex

    let preimage = try await serviceAccounts.historicalLookup(
        serviceAccount: service,
        timeslot: workPackage.context.lookupAnchor.timeslot,
        preimageHash: workItem.codeHash,
    )

    guard let preimage, try await serviceAccounts.get(serviceAccount: service) != nil else {
        return (.failure(.invalidCode), [], Gas(0))
    }

    guard preimage.count <= config.value.maxServiceCodeSize else {
        return (.failure(.codeTooLarge), [], Gas(0))
    }

    let codeBlob = try CodeAndMeta(data: preimage).codeBlob

    let argumentData = try JamEncoder.encode(
        UInt(coreIndex),
        UInt(workItemIndex),
        UInt(service),
        workItem.payloadBlob,
        workPackage.hash(),
    )

    let ctx = RefineContext(
        config: config,
        context: RefineContext.ContextType(pvms: [:], exports: []),
        importSegments: importSegments,
        exportSegmentOffset: exportSegmentOffset,
        service: service,
        serviceAccounts: serviceAccounts,
        workPackage: workPackage,
        workItemIndex: workItemIndex,
        authorizerTrace: authorizerTrace,
    )

    let (exitReason, gasUsed, output) = await invokePVM(
        config: config,
        blob: codeBlob,
        pc: 0,
        gas: workItem.refineGasLimit,
        argumentData: argumentData,
        ctx: ctx,
    )

    switch exitReason {
    case .outOfGas:
        return (.failure(.outOfGas), [], gasUsed)
    case .panic(.trap):
        return (.failure(.panic), [], gasUsed)
    default:
        if let output {
            return (.success(output), ctx.context.exports, gasUsed)
        } else {
            return (.failure(.panic), [], gasUsed)
        }
    }
}
