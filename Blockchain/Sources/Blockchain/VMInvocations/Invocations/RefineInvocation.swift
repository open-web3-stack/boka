import Codec
import Foundation
import PolkaVM
import Utils

public protocol RefineInvocation {
    func invoke(
        config: ProtocolConfigRef,
        serviceAccounts: some ServiceAccounts,
        /// Index of the work item to be refined
        workItemIndex: Int,
        /// The work package
        workPackage: WorkPackage,
        /// The output of the authorizer
        authorizerOutput: Data,
        /// all work items's import segments
        importSegments: [[Data4104]],
        /// Export segment offset
        exportSegmentOffset: UInt64
    ) async throws -> (result: Result<Data, WorkResultError>, exports: [Data4104])
}

extension RefineInvocation {
    public func invoke(
        config: ProtocolConfigRef,
        serviceAccounts: some ServiceAccounts,
        workItemIndex: Int,
        workPackage: WorkPackage,
        authorizerOutput: Data,
        importSegments: [[Data4104]],
        exportSegmentOffset: UInt64
    ) async throws -> (result: Result<Data, WorkResultError>, exports: [Data4104]) {
        let workItem = workPackage.workItems[workItemIndex]
        let service = workItem.serviceIndex

        let codeBlob = try await serviceAccounts.historicalLookup(
            serviceAccount: service,
            timeslot: workPackage.context.lookupAnchor.timeslot,
            preimageHash: workItem.codeHash
        )

        guard let codeBlob, try await serviceAccounts.get(serviceAccount: service) != nil else {
            return (.failure(.invalidCode), [])
        }

        guard codeBlob.count <= config.value.maxServiceCodeSize else {
            return (.failure(.codeTooLarge), [])
        }

        let argumentData = try await JamEncoder.encode(
            service,
            workItem.payloadBlob,
            workPackage.hash(),
            workPackage.context,
            workPackage.authorizer(serviceAccounts: serviceAccounts)
        )

        let ctx = RefineContext(
            config: config,
            context: (pvms: [:], exports: []),
            importSegments: importSegments,
            exportSegmentOffset: exportSegmentOffset,
            service: service,
            serviceAccounts: serviceAccounts,
            workPackage: workPackage,
            authorizerOutput: authorizerOutput
        )

        let (exitReason, _, output) = await invokePVM(
            config: config,
            blob: codeBlob,
            pc: 0,
            gas: workItem.refineGasLimit,
            argumentData: argumentData,
            ctx: ctx
        )

        switch exitReason {
        case .outOfGas:
            return (.failure(.outOfGas), [])
        case .panic(.trap):
            return (.failure(.panic), [])
        default:
            if let output {
                return (.success(output), ctx.context.exports)
            } else {
                return (.failure(.panic), [])
            }
        }
    }
}
