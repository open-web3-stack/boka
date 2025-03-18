import Foundation
import Synchronization
import TracingUtils
import Utils

public enum GuaranteeingServiceError: Error {
    case noAuthorizerHash
    case invalidExports
    case invalidWorkPackage
    case invalidBundle
    case segmentsRootNotFound
    case notValidator
    case invalidCore
    case unableToGetSignatures
    case authorizationError(WorkResultError)
}

public final class GuaranteeingService: ServiceBase2, @unchecked Sendable, OnBeforeEpoch, OnSyncCompleted {
    private let dataProvider: BlockchainDataProvider
    private let keystore: KeyStore
    private let dataAvailability: DataAvailability

    let signingKey: ThreadSafeContainer<(ValidatorIndex, Ed25519.SecretKey)?> = .init(nil)
    let coreAssignments: ThreadSafeContainer<([CoreIndex], TimeslotIndex)> = .init(([], 0))

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
    }

    public func onSyncCompleted() async {
        // received via p2p
        await subscribe(RuntimeEvents.WorkPackagesReceived.self, id: "GuaranteeingService.WorkPackagesReceived") { [weak self] event in
            try await self?.on(workPackagesReceived: event)
        }

        // received via RPC
        await subscribe(RuntimeEvents.WorkPackagesSubmitted.self, id: "GuaranteeingService.WorkPackagesSubmitted") { [weak self] event in
            try await self?.on(workPackagesSubmitted: event)
        }

        await subscribe(
            RuntimeEvents.WorkPackageBundleRecived.self,
            id: "GuaranteeingService.WorkPackageBundleRecived"
        ) { [weak self] event in
            try await self?.on(workPackageBundleReceived: event)
        }
    }

    public func onBeforeEpoch(epoch _: EpochIndex, safroleState: SafrolePostState) async {
        await withSpan("GuaranteeingService.onBeforeEpoch", logger: logger) { _ in
            let validators = safroleState.currentValidators

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
        try await refineWorkPackage(coreIndex: event.coreIndex, workPackage: event.workPackage, extrinsics: event.extrinsics)
    }

    private func on(workPackagesSubmitted event: RuntimeEvents.WorkPackagesSubmitted) async throws {
        try await refineWorkPackage(coreIndex: event.coreIndex, workPackage: event.workPackage, extrinsics: event.extrinsics)
    }

    private func on(workPackageBundleReceived event: RuntimeEvents.WorkPackageBundleRecived) async throws {
        let workBundleHash = event.bundle.hash()
        guard let (_, signingKey) = signingKey.value else {
            publish(RuntimeEvents.WorkPackageBundleRecivedResponse(
                workBundleHash: workBundleHash,
                error: GuaranteeingServiceError.notValidator
            ))
            return
        }

        do {
            // TODO: we may already done the work. need to cache the result
            let report = try await processWorkPackageBundle(
                coreIndex: event.coreIndex,
                segmentsRootMappings: event.segmentsRootMappings,
                bundle: event.bundle
            )

            let payload = SigningContext.guarantee + report.hash().data
            let signature = try signingKey.sign(message: payload)
            publish(RuntimeEvents.WorkPackageBundleRecivedResponse(
                workBundleHash: workBundleHash,
                workReportHash: report.hash(),
                signature: signature
            ))
        } catch {
            publish(RuntimeEvents.WorkPackageBundleRecivedResponse(
                workBundleHash: workBundleHash,
                error: error
            ))
        }
    }

    private func validateWorkPackageBundle(
        _ bundle: WorkPackageBundle,
        segmentsRootMappings: SegmentsRootMappings
    ) throws -> Bool {
        // Validate the work package authorization
        guard try validateAuthorization(bundle.workPackage) else {
            return false
        }

        // Validate the segments-root mappings
        for mapping in segmentsRootMappings {
            guard try validateSegmentsRootMapping(mapping, for: bundle.workPackage) else {
                return false
            }
        }

        return true
    }

    private func processWorkPackageBundle(
        coreIndex: CoreIndex,
        segmentsRootMappings: SegmentsRootMappings,
        bundle: WorkPackageBundle
    ) async throws -> WorkReport {
        guard let (validatorIndex, _) = signingKey.value else {
            throw GuaranteeingServiceError.notValidator
        }

        let state = try await dataProvider.getState(hash: dataProvider.bestHead.hash)

        let coreAssignment = getCoreAssignment(state: state)

        guard let currentCoreIndex = coreAssignment[safe: Int(validatorIndex)] else {
            try throwUnreachable("invalid validator index/core assignment")
        }
        guard currentCoreIndex == coreIndex else {
            throw GuaranteeingServiceError.invalidCore
        }

        let workPackage = bundle.workPackage.asRef()

        // Validate the work package
        guard try validate(workPackage: workPackage.value) else {
            logger.error("Invalid work package: \(workPackage)")
            throw GuaranteeingServiceError.invalidWorkPackage
        }

        // check & refine
        let (_, _, workReport) = try await createWorkReport(
            state: state,
            coreIndex: coreIndex,
            workPackage: workPackage,
            extrinsics: bundle.extrinsics,
            segmentsRootMappings: segmentsRootMappings
        )

        return workReport
    }

    private func refineWorkPackage(
        coreIndex: CoreIndex,
        workPackage: WorkPackageRef,
        extrinsics: [Data]
    ) async throws {
        guard let (validatorIndex, signingKey) = signingKey.value else {
            throw GuaranteeingServiceError.notValidator
        }

        let state = try await dataProvider.getState(hash: dataProvider.bestHead.hash)

        let coreAssignment = getCoreAssignment(state: state)

        guard let currentCoreIndex = coreAssignment[safe: Int(validatorIndex)] else {
            try throwUnreachable("invalid validator index/core assignment")
        }
        guard currentCoreIndex == coreIndex else {
            throw GuaranteeingServiceError.invalidCore
        }

        // Validate the work package
        guard try validate(workPackage: workPackage.value) else {
            logger.error("Invalid work package: \(workPackage)")
            throw GuaranteeingServiceError.invalidWorkPackage
        }

        // check & refine
        let (bundle, mappings, workReport) = try await createWorkReport(
            state: state,
            coreIndex: coreIndex,
            workPackage: workPackage,
            extrinsics: extrinsics,
            segmentsRootMappings: nil
        )

        let workReportHash = workReport.hash()

        var otherValidators = [(ValidatorIndex, Ed25519PublicKey)]()
        // TODO: handle the edge case and we may need to use nextValidators on epoch boundary
        let currentValidators = state.value.currentValidators
        for (idx, core) in coreAssignment.enumerated() {
            if core == coreIndex, idx != Int(validatorIndex) {
                otherValidators.append((ValidatorIndex(idx), currentValidators.array[idx].ed25519))
            }
        }

        // announce work package bundle ready via CE134 to other validators in the same core group and wait for signatures
        var sigs: [ValidatorSignature] = await withTaskGroup(of: Optional<ValidatorSignature>.self) { group in
            for (idx, validatorKey) in otherValidators {
                publish(RuntimeEvents.WorkPackageBundleReady(
                    target: validatorKey,
                    coreIndex: coreIndex,
                    bundle: bundle,
                    segmentsRootMappings: mappings
                ))
                group.addTask {
                    do {
                        let resp = try await self.waitFor(
                            eventType: RuntimeEvents.WorkPackageBundleRecivedReply.self,
                            check: { event in
                                event.source == validatorKey && event.workReportHash == workReportHash
                            },
                            timeout: 2 // TODO: make configurable? and determine the best value
                        )
                        return ValidatorSignature(validatorIndex: idx, signature: resp.signature)
                    } catch ContinuationError.timeout {
                        self.logger.debug("no reply from \(validatorKey) in time")
                        return nil
                    } catch {
                        self.logger.error("error waiting for reply from \(validatorKey)", metadata: ["error": "\(error)"])
                        return nil
                    }
                }
            }

            var results: [ValidatorSignature] = []
            for await sig in group {
                if let sig {
                    results.append(sig)
                }
            }
            return results
        }

        guard sigs.count >= 1 else {
            throw GuaranteeingServiceError.unableToGetSignatures
        }

        // Sign work report & work-report distribution via CE 135
        let payload = SigningContext.guarantee + workReport.hash().data
        let signature = try signingKey.sign(message: payload)

        sigs.append(ValidatorSignature(validatorIndex: validatorIndex, signature: signature))

        let timeslot = timeProvider.getTime().timeToTimeslot(config: config) + 1

        // Distribute the guaranteed work-report to all current validators
        publish(RuntimeEvents.WorkReportGenerated(
            workReport: workReport,
            slot: timeslot,
            signatures: sigs
        ))
    }

    private func getCoreAssignment(state: StateRef) -> [CoreIndex] {
        // TODO: this is wrong
        // instead of using timeslot from last block, we need to calculate the current timeslot and use it
        // so we can handle block gaps

        let timeslot = state.value.timeslot + 1

        let res = coreAssignments.read { c, t -> [CoreIndex]? in
            if t == timeslot {
                return c
            }
            return nil
        }

        if let res {
            return res
        }

        let newCoreAssignment = state.value.getCoreAssignment(
            config: config,
            randomness: state.value.entropyPool.t2,
            timeslot: timeslot
        )

        coreAssignments.value = (newCoreAssignment, timeslot)

        return newCoreAssignment
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

    // TODO: Add validate func
    private func validate(workPackage _: WorkPackage) throws -> Bool {
        // 1. Check if it is possible to generate a work-report
        // 2. Check all import segments have been retrieved
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
    private func createWorkReport(
        state: StateRef,
        coreIndex: CoreIndex,
        workPackage: WorkPackageRef,
        extrinsics: [Data],
        segmentsRootMappings: SegmentsRootMappings?
    ) async throws -> (WorkPackageBundle, SegmentsRootMappings, WorkReport) {
        let packageHash = workPackage.hash
        let corePool = state.value.coreAuthorizationPool[coreIndex]
        let authorizerHash = try corePool.array.first.unwrap(orError: GuaranteeingServiceError.noAuthorizerHash)
        var exportSegmentOffset: UInt16 = 0
        var mappings: SegmentsRootMappings = []

        let res = try await isAuthorized(config: config, serviceAccounts: state.value, package: workPackage.value, coreIndex: coreIndex)
        let authorizationOutput = try res.mapError(GuaranteeingServiceError.authorizationError).get()

        var workResults = [WorkResult]()

        var exportSegments = [Data4104]()

        // TODO: make this lazy, only fetch when needed by PVM
        var importSegments = [[Data4104]]()
        for item in workPackage.value.workItems {
            let segment = try await dataAvailability.fetchSegment(segments: item.inputs, segmentsRootMappings: segmentsRootMappings)
            importSegments.append(segment)
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
            extrinsics: extrinsics,
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
    }
}
