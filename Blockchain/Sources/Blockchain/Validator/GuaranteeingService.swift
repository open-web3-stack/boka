import Foundation
import Synchronization
import TracingUtils
import Utils

public enum GuaranteeingServiceError: Error {
    case noAuthorizerHash
    case invalidExports
}

public struct SegmentsRootMapping: Codable {
    public let workPackageHash: Data32
    public let segmentsRoot: SegmentsRoot
}

public typealias SegmentsRoot = Data32
public typealias SegmentsRootMappings = [SegmentsRootMapping]

public struct Guarantor: Codable, Identifiable {
    public let id: Data32 // Unique identifier for the guarantor (e.g., public key hash)
    public let coreIndex: CoreIndex // The core index to which the guarantor is assigned

    // Method to receive a work package bundle
    public func receiveWorkPackageBundle(
        coreIndex _: CoreIndex,
        segmentsRootMappings: SegmentsRootMappings,
        bundle: WorkPackageBundle
    ) async throws {
        // 1. Perform basic verification
        guard try validateWorkPackageBundle(bundle, segmentsRootMappings: segmentsRootMappings) else {
            throw WorkPackageError.invalidBundle
        }
    }

    private func validateWorkPackageBundle(
        _ bundle: WorkPackageBundle,
        segmentsRootMappings: SegmentsRootMappings
    ) throws -> Bool {
        // 1. Validate the work package authorization
        guard try validateAuthorization(bundle.workPackage) else {
            return false
        }

        // 2. Validate the segments-root mappings
        for mapping in segmentsRootMappings {
            guard try validateSegmentsRootMapping(mapping, for: bundle.workPackage) else {
                return false
            }
        }

        return true
    }

    private func validateSegmentsRootMapping(
        _: SegmentsRootMapping,
        for _: WorkPackage
    ) throws -> Bool {
        // TODO: Implement logic to validate the segments-root mapping
        true // Placeholder
    }

    private func validateAuthorization(_: WorkPackage) throws -> Bool {
        // TODO: Implement logic to validate the work package authorization
        true // Placeholder
    }
}

public final class GuaranteeingService: ServiceBase2, @unchecked Sendable {
    private let dataProvider: BlockchainDataProvider
    private let keystore: KeyStore
    private let dataAvailability: DataAvailability

    let signingKey: ThreadSafeContainer<(ValidatorIndex, Ed25519.SecretKey)?> = .init(nil)

    public init(
        config: ProtocolConfigRef,
        eventBus: EventBus,
        scheduler: Scheduler,
        dataProvider: BlockchainDataProvider,
        keystore: KeyStore,
        dataStore: DataStore
    ) async {
        self.dataProvider = dataProvider
        self.keystore = keystore
        dataAvailability = await DataAvailability(
            config: config,
            eventBus: eventBus,
            scheduler: scheduler,
            dataProvider: dataProvider,
            dataStore: dataStore
        )

        super.init(id: "GuaranteeingService", config: config, eventBus: eventBus, scheduler: scheduler)

        await subscribe(RuntimeEvents.WorkPackagesReceived.self, id: "GuaranteeingService.WorkPackagesReceived") { [weak self] event in
            try await self?.on(workPackagesReceived: event)
        }
    }

    public func onSyncCompleted() async {
        let nowTimeslot = timeProvider.getTime().timeToTimeslot(config: config)
        let epoch = nowTimeslot.timeslotToEpochIndex(config: config)
        await onBeforeEpoch(epoch: epoch)

        scheduleForNextEpoch("GuaranteeingService.scheduleForNextEpoch") { [weak self] epoch in
            await self?.onBeforeEpoch(epoch: epoch)
        }
    }

    private func onBeforeEpoch(epoch: EpochIndex) async {
        await withSpan("GuaranteeingService.onBeforeEpoch", logger: logger) { _ in
            let state = try await dataProvider.getState(hash: dataProvider.bestHead.hash)
            let timeslot = epoch.epochToTimeslotIndex(config: config)
            // simulate next block to determine the correct current validators
            // this is more accurate than just using nextValidators from current state
            let res = try state.value.updateSafrole(
                config: config,
                slot: timeslot,
                entropy: Data32(),
                offenders: [],
                extrinsics: .dummy(config: config)
            )
            let validators = res.state.currentValidators

            let keys = await keystore.getAll(Ed25519.self)
            var result: (ValidatorIndex, Ed25519.SecretKey)?
            for key in keys {
                if let idx = validators.array.firstIndex(where: { $0.ed25519 == key.publicKey.data }) {
                    result = (ValidatorIndex(idx), key)
                    break
                }
            }

            signingKey.value = result
        }
    }

    private func on(workPackagesReceived event: RuntimeEvents.WorkPackagesReceived) async throws {
        try await shareWorkPackage(coreIndex: event.coreIndex, workPackage: event.workPackageRef, extrinsics: event.extrinsics)
    }

    // Work Package Sharing (Send Side)
    public func shareWorkPackage(coreIndex _: CoreIndex, workPackage: WorkPackageRef, extrinsics: [Data]) async throws {
        try await refinePkg(workPackage: workPackage, extrinsics: extrinsics)
    }

    private func refinePkg(workPackage: WorkPackageRef, extrinsics: [Data]) async throws {
        guard let (validatorIndex, signingKey) = signingKey.value else {
            logger.debug("not in current validator set, skipping refine")
            return
        }

        let state = try await dataProvider.getState(hash: dataProvider.bestHead.hash)

        // TODO: check for edge cases such as epoch end
        let currentCoreAssignment = state.value.getCoreAssignment(
            config: config,
            randomness: state.value.entropyPool.t2,
            timeslot: state.value.timeslot + 1
        )
        // TODO: coreIndex equal with shareWorkPackage coreIndex?
        guard let coreIndex = currentCoreAssignment[safe: Int(validatorIndex)] else {
            try throwUnreachable("invalid validator index/core assignment")
        }
        // TODO: validatorIndex -> coreIndex
        // 1. TODO: Get other guarantors assigned to the same core
        let guarantors = try await getGuarantors(for: coreIndex)

        // 2. Validate the work package
        guard try validate(workPackage: workPackage.value) else {
            logger.error("Invalid work package: \(workPackage)")
            throw WorkPackageError.invalidWorkPackage
        }

        // 3. Create work report & WorkPackageBundle
        let (bundle, mappings, workReport) = try await createWorkReport(
            coreIndex: coreIndex,
            workPackage: workPackage,
            extrinsics: extrinsics
        )
        // 4. TODO: Send the bundle to other guarantors
        for guarantor in guarantors {
            // 5. TODO: Something needs to do, when receive workpackage bundle
            try await guarantor.receiveWorkPackageBundle(
                coreIndex: coreIndex,
                segmentsRootMappings: mappings,
                bundle: bundle
            )
        }
        // 6. Sign the work report hash
        let payload = SigningContext.guarantee + workReport.hash().data
        let signature = try signingKey.sign(message: payload)
        let event = RuntimeEvents.WorkReportGenerated(item: workReport, signature: signature)
        // 7. Push
        publish(event)
    }

    // TODO: Get other guarantors assigned to the same core
    public func getGuarantors(for coreIndex: CoreIndex) async throws -> [Guarantor] {
        // 1. Get the current blockchain state
        let state = try await dataProvider.getState(hash: dataProvider.bestHead.hash)
        var guarantors = [Guarantor]()
        // TODO: Mock
        for (_, v) in state.value.currentValidators.enumerated() {
            guarantors.append(Guarantor(
                id: v.ed25519.blake2b256hash(), // Use the validator's public key hash as the ID
                coreIndex: coreIndex
            ))
        }
        return guarantors
    }

    private func validate(workPackage _: WorkPackage) throws -> Bool {
        // TODO: Add validate func
        true
    }

    private func retrieveImportSegments(for _: WorkPackage) async throws -> [Data4104] {
        // TODO: Implement retrieveImportSegments
        // Implement logic to retrieve imported data segments
        // For example, fetch from the data availability layer
        [] // Placeholder
    }

    private func retrieveJustifications(for _: WorkPackage) async throws -> [Data] {
        // TODO: Implement retrieveJustifications
        // Implement logic to retrieve justifications for the imported segments
        // For example, fetch proofs from the data availability layer
        [] // Placeholder
    }

    // workpackage -> workresult -> workreport
    private func createWorkReport(coreIndex: CoreIndex, workPackage: WorkPackageRef,
                                  extrinsics: [Data]) async throws -> (WorkPackageBundle, SegmentsRootMappings, WorkReport)
    {
        let state = try await dataProvider.getState(hash: dataProvider.bestHead.hash)
        let packageHash = workPackage.hash
        let corePool = state.value.coreAuthorizationPool[coreIndex]
        let authorizerHash = try corePool.array.first.unwrap(orError: GuaranteeingServiceError.noAuthorizerHash)
        var exportSegmentOffset: UInt16 = 0
        var mappings: SegmentsRootMappings = []
        // B.2. the authorization output, the result of the Is-Authorized function
        // TODO: waiting for authorizationFunction done  Mock a result
        // let res = try await authorizationFunction.invoke(config: config, serviceAccounts: state.value, package: workPackage, coreIndex:
        // coreIndex)
        let res = Result<Data, WorkResultError>.success(Data())
        switch res {
        // authorizationFunction -> authorizationOutput
        case let .success(authorizationOutput):
            var workResults = [WorkResult]()

            var exportSegments = [Data4104]()

            // TODO: make this lazy, only fetch when needed by PVM
            var importSegments = [[Data4104]]()
            for item in workPackage.value.workItems {
                try await importSegments.append(dataAvailability.fetchSegment(segments: item.inputs))
            }

            for (i, item) in workPackage.value.workItems.enumerated() {
                // refine data to workresult
                let refineRes = try await refine(
                    config: config,
                    serviceAccounts: state.value,
                    workItemIndex: i,
                    workPackage: workPackage.value,
                    authorizerOutput: authorizationOutput,
                    importSegments: importSegments,
                    exportSegmentOffset: UInt64(exportSegmentOffset)
                )
                // Export -> DA or exportSegmentOffset + outputDataSegmentsCount ？
                exportSegmentOffset += item.outputDataSegmentsCount
                let workResult = WorkResult(
                    serviceIndex: item.serviceIndex,
                    codeHash: workPackage.value.authorizationCodeHash,
                    payloadHash: item.payloadBlob.blake2b256hash(),
                    gas: item.refineGasLimit,
                    output: WorkOutput(refineRes.result)
                )
                workResults.append(workResult)

                guard item.outputDataSegmentsCount == refineRes.exports.count else {
                    throw GuaranteeingServiceError.invalidExports
                }

                exportSegments.append(contentsOf: refineRes.exports)
            }
            let bundle = try await WorkPackageBundle(
                workPackage: workPackage.value,
                extrinsic: extrinsics,
                importSegments: retrieveImportSegments(for: workPackage.value),
                justifications: retrieveJustifications(for: workPackage.value)
            )
            let (erasureRoot, length) = try await dataAvailability.exportWorkpackageBundle(bundle: bundle)

            let segmentRoot = try await dataAvailability.exportSegments(data: exportSegments, erasureRoot: erasureRoot)
            mappings.append(SegmentsRootMapping(workPackageHash: packageHash, segmentsRoot: segmentRoot))
            // TODO: generate or find AvailabilitySpecifications  14.4.1 work-package bundle
            let packageSpecification = AvailabilitySpecifications(
                workPackageHash: packageHash,
                length: length,
                erasureRoot: erasureRoot,
                segmentRoot: segmentRoot,
                segmentCount: exportSegmentOffset
            )
            // The historical lookup function, Λ, is defined in equation 9.7.
            var oldLookups = [Data32: Data32]()
            for item in state.value.recentHistory.items {
                oldLookups.merge(item.lookup, uniquingKeysWith: { _, new in new })
            }
            return try (bundle, mappings, WorkReport(
                authorizerHash: authorizerHash,
                coreIndex: coreIndex,
                authorizationOutput: authorizationOutput,
                refinementContext: workPackage.value.context,
                packageSpecification: packageSpecification,
                lookup: oldLookups,
                results: ConfigLimitedSizeArray(config: config, array: workResults)
            ))

        case let .failure(error):
            logger.error("Authorization failed with error: \(error)")
            throw error
        }
    }
}
