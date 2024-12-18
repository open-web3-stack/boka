import Codec
import Foundation
import PolkaVM
import Utils

public protocol RefineInvocation {
    func invoke(
        config: ProtocolConfigRef,
        serviceAccounts: some ServiceAccounts,
        codeHash: Data,
        gas: Gas,
        service: ServiceIndex,
        workPackageHash: Data32,
        workPayload: Data,
        refinementCtx: RefinementContext,
        authorizerHash: Data32,
        authorizationOutput: Data,
        importSegments: [Data], // array of Data4104
        extrinsicDataBlobs: [Data],
        exportSegmentOffset: UInt64
    ) async throws -> (result: Result<Data, WorkResultError>, exports: [Data])
}

extension RefineInvocation {
    func invoke(
        config: ProtocolConfigRef,
        serviceAccounts: some ServiceAccounts,
        codeHash: Data32,
        gas: Gas,
        service: ServiceIndex,
        workPackageHash: Data32,
        workPayload: Data, // y
        refinementCtx: RefinementContext, // c
        authorizerHash: Data32,
        authorizationOutput: Data,
        importSegments: [Data],
        extrinsicDataBlobs: [Data],
        exportSegmentOffset: UInt64
    ) async throws -> (result: Result<Data, WorkResultError>, exports: [Data]) {
        let codeBlob = try await serviceAccounts.historicalLookup(
            serviceAccount: service,
            timeslot: refinementCtx.lookupAnchor.timeslot,
            preimageHash: codeHash
        )

        guard let codeBlob, try await serviceAccounts.get(serviceAccount: service) != nil else {
            return (.failure(.invalidCode), [])
        }

        guard codeBlob.count <= config.value.maxServiceCodeSize else {
            return (.failure(.codeTooLarge), [])
        }

        let argumentData = try JamEncoder.encode(
            service,
            workPayload,
            workPackageHash,
            refinementCtx,
            authorizerHash,
            authorizationOutput,
            extrinsicDataBlobs
        )
        let ctx = RefineContext(
            config: config,
            context: (pvms: [:], exports: []),
            importSegments: importSegments,
            exportSegmentOffset: exportSegmentOffset,
            service: service,
            serviceAccounts: serviceAccounts,
            lookupAnchorTimeslot: refinementCtx.lookupAnchor.timeslot
        )

        let (exitReason, _, output) = await invokePVM(
            config: config,
            blob: codeBlob,
            pc: 0,
            gas: gas,
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
