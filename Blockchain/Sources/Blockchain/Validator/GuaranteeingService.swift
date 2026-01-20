import Codec
import Foundation
import PolkaVM
import Synchronization
import TracingUtils
import Utils

public enum GuaranteeingServiceError: Error, Equatable {
    case noAuthorizerHash
    case invalidExports
    case invalidWorkPackage
    case invalidBundle
    case bundleSizeExceeded
    case segmentsRootNotFound
    case notValidator
    case invalidCore
    case unableToGetSignatures
    case authorizationError(WorkResultError)
    case importSegmentsNotFound
    case invalidImportSegmentCount
    case dataAvailabilityError
    case serviceAccountNotFound
}

/// Service for managing work guarantees and validation
///
/// Thread-safety: @unchecked Sendable is safe here because:
/// - Inherits safety from ServiceBase2 (immutable properties + ThreadSafeContainer)
/// - All mutable state is protected by ThreadSafeContainer instances
/// - signingKey, coreAssignments, and workReportCache are synchronized
public final class GuaranteeingService: ServiceBase2, @unchecked Sendable, OnBeforeEpoch, OnSyncCompleted {
    private let dataProvider: BlockchainDataProvider
    private let keystore: KeyStore
    private let dataAvailability: DataAvailabilityService
    private let executionMode: ExecutionMode

    // Stores the current signing key and validator index
    let signingKey: ThreadSafeContainer<(ValidatorIndex, Ed25519.SecretKey)?> = .init(nil)

    // Stores the core assignments for a specific timeslot
    let coreAssignments: ThreadSafeContainer<([CoreIndex], TimeslotIndex)> = .init(([], 0))

    // Cache for processed work package results to avoid duplicate work
    let workReportCache = ThreadSafeContainer<[Data32: WorkReport]>([:])

    public init(
        config: ProtocolConfigRef,
        eventBus: EventBus,
        scheduler: Scheduler,
        dataProvider: BlockchainDataProvider,
        keystore: KeyStore,
        dataStore: DataStore,
        executionMode: ExecutionMode = []
    ) async {
        self.dataProvider = dataProvider
        self.keystore = keystore
        self.executionMode = executionMode
        dataAvailability = await DataAvailabilityService(
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
            RuntimeEvents.WorkPackageBundleReceived.self,
            id: "GuaranteeingService.WorkPackageBundleReceived"
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

    private func on(workPackageBundleReceived event: RuntimeEvents.WorkPackageBundleReceived) async throws {
        let workBundleHash = event.bundle.hash()
        guard let (_, signingKey) = signingKey.value else {
            publish(RuntimeEvents.WorkPackageBundleReceivedResponse(
                workBundleHash: workBundleHash,
                error: GuaranteeingServiceError.notValidator
            ))
            return
        }

        do {
            // Work report caching is already implemented in processWorkPackageBundle
            let report = try await processWorkPackageBundle(
                coreIndex: event.coreIndex,
                segmentsRootMappings: event.segmentsRootMappings,
                bundle: event.bundle
            )

            let payload = SigningContext.guarantee + report.hash().data
            let signature = try signingKey.sign(message: payload)
            publish(RuntimeEvents.WorkPackageBundleReceivedResponse(
                workBundleHash: workBundleHash,
                workReportHash: report.hash(),
                signature: signature
            ))
        } catch {
            publish(RuntimeEvents.WorkPackageBundleReceivedResponse(
                workBundleHash: workBundleHash,
                error: error
            ))
        }
    }

    /**
     * Validates a work package bundle and its associated segments root mappings.
     *
     * As per GP section 14, this validates the work package authorization
     * and ensures all required conditions are met before guaranteeing.
     *
     * @param bundle The work package bundle to validate
     * @param segmentsRootMappings The mappings of work package hashes to segment roots
     */
    func validateWorkPackageBundle(
        _ bundle: WorkPackageBundle,
        segmentsRootMappings: SegmentsRootMappings
    ) async throws {
        try validate(workPackage: bundle.workPackage)

        try await validateAuthorization(bundle.workPackage)

        for mapping in segmentsRootMappings {
            try validateSegmentsRootMapping(mapping, for: bundle.workPackage)
        }

        try validateImportedSegments(bundle)
        try validateBundleSize(bundle)
    }

    /**
     * Validates that the imported segments in a bundle match the work items' input declarations.
     *
     * This is part of the validation process described in GP section 14, ensuring
     * that all declared inputs are present and valid.
     *
     * @param bundle The work package bundle to validate
     */
    func validateImportedSegments(_ bundle: WorkPackageBundle) throws {
        let importSegmentCount = bundle.workPackage.workItems.array.flatMap(\.inputs).count

        if bundle.importSegments.count != importSegmentCount {
            logger.debug("Import segment count mismatch",
                         metadata: ["expected": "\(importSegmentCount)", "actual": "\(bundle.importSegments.count)"])
            throw GuaranteeingServiceError.invalidImportSegmentCount
        }
    }

    /**
     * Validate bundle size
     *
     * @param bundle The work package bundle to validate
     */
    func validateBundleSize(_ bundle: WorkPackageBundle) throws {
        let bundleSize = bundle.workPackage.authorizationToken.count
            + bundle.workPackage.configurationBlob.count
            + bundle.workPackage.workItems.array.reduce(0) { total, item in
                let extrinsicsSize = item.outputs.reduce(0) { $0 + Int($1.length) }
                return total + item.payloadBlob.count
                    + item.inputs.count * config.value.segmentFootprint
                    + extrinsicsSize
            }

        guard bundleSize <= config.value.maxEncodedWorkPackageSize else {
            logger.debug("Bundle size exceeds limit",
                         metadata: ["actual": "\(bundleSize)", "limit": "\(config.value.maxEncodedWorkPackageSize)"])
            throw GuaranteeingServiceError.bundleSizeExceeded
        }
    }

    /**
     * Processes a work package bundle to create a work report.
     * This is the core function that validates, processes, and generates a work report from a bundle.
     *
     * As per GP section 14.4, this implements the work-report creation process:
     * r = Ξ(p, c) where p is the work package and c is the core index.
     *
     * @param coreIndex The core index to process the bundle for
     * @param segmentsRootMappings The mappings of work package hashes to segment roots
     * @param bundle The work package bundle to process
     * @return A work report generated from the bundle
     */
    func processWorkPackageBundle(
        coreIndex: CoreIndex,
        segmentsRootMappings: SegmentsRootMappings,
        bundle: WorkPackageBundle
    ) async throws -> WorkReport {
        guard let (validatorIndex, _) = signingKey.value else {
            throw GuaranteeingServiceError.notValidator
        }

        let workPackageHash = bundle.workPackage.hash()
        if let cachedReport = workReportCache.value[workPackageHash] {
            logger.debug("Using cached work report for bundle", metadata: ["workPackageHash": "\(workPackageHash)"])
            return cachedReport
        }

        let state = try await dataProvider.getState(hash: dataProvider.bestHead.hash)

        let coreAssignment = getCoreAssignment(state: state)

        guard let currentCoreIndex = coreAssignment[safe: Int(validatorIndex)] else {
            try throwUnreachable("invalid validator index/core assignment")
        }
        guard currentCoreIndex == coreIndex else {
            logger.error(
                "Invalid core assignment",
                metadata: ["expectedCore": "\(currentCoreIndex)", "actualCore": "\(coreIndex)"]
            )
            throw GuaranteeingServiceError.invalidCore
        }

        let workPackage = bundle.workPackage.asRef()

        try await validateWorkPackageBundle(bundle, segmentsRootMappings: segmentsRootMappings)

        let (_, _, workReport) = try await createWorkReport(
            state: state,
            coreIndex: coreIndex,
            workPackage: workPackage,
            extrinsics: bundle.extrinsics,
            segmentsRootMappings: segmentsRootMappings
        )

        var cacheValue = workReportCache.value
        cacheValue[workPackageHash] = workReport
        workReportCache.value = cacheValue

        return workReport
    }

    /**
     * Processes a work package by refining it, generating a work report, collecting signatures,
     * and distributing the final work report.
     *
     * This implements the full guaranteeing workflow described in GP section 14:
     * - Validates the work package
     * - Creates a work report
     * - Collects signatures from other validators
     * - Distributes the signed work report
     *
     * @param coreIndex The core index to process the work package for
     * @param workPackage The work package to process
     * @param extrinsics The extrinsics associated with the work package
     */
    func refineWorkPackage(
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

        try validate(workPackage: workPackage.value)

        let (bundle, mappings, workReport) = try await createWorkReport(
            state: state,
            coreIndex: coreIndex,
            workPackage: workPackage,
            extrinsics: extrinsics,
            segmentsRootMappings: nil
        )

        let workReportHash = workReport.hash()

        var otherValidators = [(ValidatorIndex, Ed25519PublicKey)]()

        let currentValidators = state.value.currentValidators
        for (idx, core) in coreAssignment.enumerated() {
            if core == coreIndex, idx != Int(validatorIndex) {
                otherValidators.append((ValidatorIndex(idx), currentValidators.array[idx].ed25519))
            }
        }

        logger.debug(
            "Requesting signatures from validators",
            metadata: ["validatorCount": "\(otherValidators.count)", "coreIndex": "\(coreIndex)"]
        )

        // Announce work package bundle ready to other validators in the same core group and wait for signatures
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
                            eventType: RuntimeEvents.WorkPackageBundleReceivedReply.self,
                            check: { event in
                                event.source == validatorKey && event.workReportHash == workReportHash
                            },
                            // Timeout in seconds for validator response.
                            // Value of 2s is reasonable for local network; may need adjustment for WAN.
                            // Consider making this a ProtocolConfig parameter for tuning.
                            timeout: 2
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

        // Ensure we have enough signatures (at least one from other validators)
        guard sigs.count >= 1 else {
            logger.error("Failed to collect enough signatures",
                         metadata: ["required": "1", "received": "\(sigs.count)"])
            throw GuaranteeingServiceError.unableToGetSignatures
        }

        // Sign work report & work-report distribution via CE 135
        let payload = SigningContext.guarantee + workReport.hash().data
        let signature = try signingKey.sign(message: payload)

        sigs.append(ValidatorSignature(validatorIndex: validatorIndex, signature: signature))

        // Calculate the timeslot for the work report (current time + 1)
        let currentTime = timeProvider.getTime()
        let timeslot = currentTime.timeToTimeslot(config: config) + 1

        // Save GuaranteedWorkReport to local db
        try await dataProvider
            .add(guaranteedWorkReport:
                GuaranteedWorkReportRef(GuaranteedWorkReport(
                    workReport: workReport,
                    slot: timeslot,
                    signatures: sigs
                )))
        // Distribute the guaranteed work-report to all current validators
        publish(RuntimeEvents.WorkReportGenerated(
            workReport: workReport,
            slot: timeslot,
            signatures: sigs
        ))
    }

    func getCoreAssignment(state: StateRef) -> [CoreIndex] {
        let currentTime = timeProvider.getTime()
        let timeslot = currentTime.timeToTimeslot(config: config)

        let res = coreAssignments.read { c, t -> [CoreIndex]? in
            if t == timeslot {
                return c
            }
            return nil
        }

        if let res {
            return res
        }

        // Generate a new assignment using the current entropy pool
        let newCoreAssignment = state.value.getCoreAssignment(
            config: config,
            randomness: state.value.entropyPool.t2,
            timeslot: timeslot
        )

        coreAssignments.value = (newCoreAssignment, timeslot)

        return newCoreAssignment
    }

    /**
     * Validates a segments root mapping against a work package.
     *
     * This is part of the validation process described in GP section 14.4,
     * ensuring that segment root mappings are valid and properly formed.
     *
     * @param mapping The mapping to validate
     * @param for The work package the mapping is for
     */
    func validateSegmentsRootMapping(
        _ mapping: SegmentsRootMapping,
        for workPackage: WorkPackage
    ) throws {
        // Verify the mapping belongs to this work package
        guard mapping.workPackageHash == workPackage.hash() else {
            logger.debug("Segment root mapping work package hash mismatch")
            throw GuaranteeingServiceError.segmentsRootNotFound
        }

        // Validate the segment root is properly formed (not all zeros)
        guard mapping.segmentsRoot != Data32() else {
            logger.debug("Empty segments root in mapping")
            throw GuaranteeingServiceError.segmentsRootNotFound
        }

        // Additional validations could be added here based on the protocol requirements
    }

    /**
     * Validates the authorization of a work package by verifying:
     * 1. The authorization token is valid
     * 2. The service account exists and has appropriate permissions
     * 3. The code hash matches the expected value
     *
     * As per GP section 14.3, this validates the work package against the
     * authorization pool in the most recent chain state.
     *
     * @param workPackage The work package to validate
     */
    func validateAuthorization(_ workPackage: WorkPackage) async throws {
        // Get the current state
        let head = await dataProvider.bestHead
        let state = try await dataProvider.getState(hash: head.hash)

        // Verify the service account exists
        guard let serviceAccount = try? await state.value.serviceAccount(index: workPackage.authorizationServiceIndex) else {
            logger.debug("Service account does not exist",
                         metadata: ["serviceIndex": "\(workPackage.authorizationServiceIndex)"])
            throw GuaranteeingServiceError.serviceAccountNotFound
        }

        // Verify the code hash matches
        guard serviceAccount.codeHash == workPackage.authorizationCodeHash else {
            logger.debug("Authorization code hash mismatch",
                         metadata: ["expected": "\(serviceAccount.codeHash)", "actual": "\(workPackage.authorizationCodeHash)"])
            throw GuaranteeingServiceError.authorizationError(.badExports)
        }

        // Attempt to run the isAuthorized function
        let result = try await isAuthorized(
            config: config,
            serviceAccounts: state.value,
            package: workPackage,
            coreIndex: 0 // The authorization doesn't depend on the core index
        )

        // Check if the result is a success or failure
        switch result.0 {
        case .success:
            return
        case let .failure(error):
            throw GuaranteeingServiceError.authorizationError(error)
        }
    }

    /**
     * Validates a work package by verifying:
     * 1. The work items are valid
     * 2. The gas limits are within bounds
     * 3. The refinement context is valid
     *
     * This implements the validation requirements described in GP section 14.3,
     * ensuring the work package meets all requirements before processing.
     *
     * @param workPackage The work package to validate
     */
    func validate(workPackage: WorkPackage) throws {
        // Basic validation checks
        guard !workPackage.workItems.array.isEmpty else {
            logger.debug("Work package has no work items")
            throw GuaranteeingServiceError.invalidWorkPackage
        }

        // Validate gas limits
        var totalRefineGas = Gas(0)
        var totalAccumulateGas = Gas(0)

        for item in workPackage.workItems {
            totalRefineGas += item.refineGasLimit
            totalAccumulateGas += item.accumulateGasLimit
        }

        // Check total refine gas
        guard totalRefineGas < config.value.workPackageRefineGas else {
            logger.debug("Work package total refine gas exceeds limit",
                         metadata: ["actual": "\(totalRefineGas)", "limit": "\(config.value.workPackageRefineGas)"])
            throw GuaranteeingServiceError.invalidWorkPackage
        }

        // Check total accumulate gas
        guard totalAccumulateGas < config.value.workReportAccumulationGas else {
            logger.debug("Work package total accumulate gas exceeds limit",
                         metadata: ["actual": "\(totalAccumulateGas)", "limit": "\(config.value.workReportAccumulationGas)"])
            throw GuaranteeingServiceError.invalidWorkPackage
        }

        // Validate the refinement context
        let context = workPackage.context
        guard context.prerequisiteWorkPackages.count <= config.value.maxDepsInWorkReport else {
            logger.debug("Too many prerequisite work packages",
                         metadata: ["count": "\(context.prerequisiteWorkPackages.count)",
                                    "limit": "\(config.value.maxDepsInWorkReport)"])
            throw GuaranteeingServiceError.invalidWorkPackage
        }
    }

    /**
     * Retrieves imported segments for a work package.
     *
     * As described in GP section 14.3-14.4, this retrieves the necessary
     * data segments for processing the work package.
     *
     * @param for The work package to retrieve segments for
     * @return An array of data segments
     */
    func retrieveImportSegments(for workPackage: WorkPackage) async throws -> [Data4104] {
        var segments = [Data4104]()

        let importSegments = workPackage.workItems.array.flatMap(\.inputs)

        for segment in importSegments {
            switch segment.root {
            case let .segmentRoot(root):
                // Fetch from data availability layer using segment root
                // This is a simplified implementation - in a real implementation, we would fetch from the data store
                logger.debug("Fetching segment by root", metadata: ["root": "\(root)", "index": "\(segment.index)"])
                segments.append(Data4104())

            case let .workPackageHash(hash):
                // Fetch from data availability layer using work package hash
                // This is a simplified implementation - in a real implementation, we would fetch from the data store
                logger.debug("Fetching segment by hash", metadata: ["hash": "\(hash)", "index": "\(segment.index)"])
                segments.append(Data4104())
            }
        }

        return segments
    }

    /**
     * Retrieves justifications for imported segments.
     *
     * This supports the data availability requirements described in GP section 14.3-14.4,
     * providing proofs for the imported segments.
     *
     * @param for The work package to retrieve justifications for
     * @return An array of justification data
     */
    func retrieveJustifications(for workPackage: WorkPackage) async throws -> [Data] {
        var justifications = [Data]()

        let importSegments = workPackage.workItems.array.flatMap(\.inputs)

        for segment in importSegments {
            switch segment.root {
            case let .segmentRoot(root):
                // Fetch justification from data availability layer using segment root
                // This is a simplified implementation - in a real implementation, we would fetch from the data store
                logger.debug("Fetching proof for segment by root", metadata: ["root": "\(root)", "index": "\(segment.index)"])
                justifications.append(Data())

            case let .workPackageHash(hash):
                // Fetch justification from data availability layer using work package hash
                // This is a simplified implementation - in a real implementation, we would fetch from the data store
                logger.debug("Fetching proof for segment by hash", metadata: ["hash": "\(hash)", "index": "\(segment.index)"])
                justifications.append(Data())
            }
        }

        return justifications
    }

    /**
     * Creates a work report from a work package.
     * This function executes the full processing pipeline:
     * 1. Authorizes the work package
     * 2. Refines each work item
     * 3. Exports the resulting segments to data availability
     * 4. Creates and returns a work report
     *
     * This implements the core work report creation process described in GP section 14.2:
     * r = Ξ(p, c) where p is the work package and c is the core index.
     *
     * It also handles the chunking and distribution of data as per GP section 14.3,
     * and creates the availability specifications as described in GP section 14.4.
     *
     * @param state The current state reference
     * @param coreIndex The core index processing this work package
     * @param workPackage The work package to process
     * @param extrinsics The extrinsics associated with the work package
     * @param segmentsRootMappings Optional mappings of work package hashes to segment roots
     * @return A tuple containing the bundle, mappings, and work report
     */
    func createWorkReport(
        state: StateRef,
        coreIndex: CoreIndex,
        workPackage: WorkPackageRef,
        extrinsics: [Data],
        segmentsRootMappings: SegmentsRootMappings?
    ) async throws -> (WorkPackageBundle, SegmentsRootMappings, WorkReport) {
        // Check cache first
        let packageHash = workPackage.hash
        if let cachedReport = workReportCache.value[packageHash] {
            let imports = try await retrieveImportSegments(for: workPackage.value)
            let justifications = try await retrieveJustifications(for: workPackage.value)

            let bundle = WorkPackageBundle(
                workPackage: workPackage.value,
                extrinsics: extrinsics,
                importSegments: imports,
                justifications: justifications
            )

            let mappings: SegmentsRootMappings = [
                SegmentsRootMapping(
                    workPackageHash: packageHash,
                    segmentsRoot: cachedReport.packageSpecification.segmentRoot
                ),
            ]

            return (bundle, mappings, cachedReport)
        }

        let corePool = state.value.coreAuthorizationPool[coreIndex]
        guard let authorizerHash = corePool.array.first else {
            logger.error("No authorizer hash found for core", metadata: ["coreIndex": "\(coreIndex)"])
            throw GuaranteeingServiceError.noAuthorizerHash
        }

        var exportSegmentOffset: UInt16 = 0
        var mappings: SegmentsRootMappings = []

        logger.debug("Authorizing work package", metadata: ["workPackageHash": "\(packageHash)"])
        let (authRes, authGasUsed) = try await isAuthorized(
            config: config,
            executionMode: executionMode,
            serviceAccounts: state.value,
            package: workPackage.value,
            coreIndex: coreIndex
        )
        let authorizerTrace = try authRes.mapError(GuaranteeingServiceError.authorizationError).get()
        logger.debug("Work package authorized successfully", metadata: ["traceSize": "\(authorizerTrace.count)"])

        var workDigests = [WorkDigest]()
        var exportSegments = [Data4104]()

        var importSegments = [[Data4104]]()
        for item in workPackage.value.workItems {
            let segment = try await dataAvailability.fetchSegment(segments: item.inputs, segmentsRootMappings: segmentsRootMappings)
            importSegments.append(segment)
        }

        logger.debug("Processing work items", metadata: ["itemCount": "\(workPackage.value.workItems.count)"])

        for (i, item) in workPackage.value.workItems.enumerated() {
            logger.debug("Refining work item",
                         metadata: ["itemIndex": "\(i)", "serviceIndex": "\(item.serviceIndex)"])

            let (refineRes, refineExports, refineGasUsed) = try await refine(
                config: config,
                executionMode: executionMode,
                serviceAccounts: state.value,
                workItemIndex: i,
                workPackage: workPackage.value,
                coreIndex: coreIndex,
                authorizerTrace: authorizerTrace,
                importSegments: importSegments,
                exportSegmentOffset: UInt64(exportSegmentOffset)
            )

            exportSegmentOffset += item.exportsCount
            let workDigest = WorkDigest(
                serviceIndex: item.serviceIndex,
                codeHash: workPackage.value.authorizationCodeHash,
                payloadHash: item.payloadBlob.blake2b256hash(),
                gasLimit: item.refineGasLimit,
                result: WorkResult(refineRes),
                gasUsed: UInt(refineGasUsed.value),
                importsCount: UInt(item.inputs.count),
                exportsCount: UInt(item.exportsCount),
                extrinsicsCount: UInt(item.outputs.count),
                extrinsicsSize: UInt(item.outputs.reduce(into: 0) { $0 += $1.length })
            )
            workDigests.append(workDigest)

            guard item.exportsCount == refineExports.count else {
                logger.error("Export segment count mismatch",
                             metadata: ["expected": "\(item.exportsCount)", "actual": "\(refineExports.count)"])
                throw GuaranteeingServiceError.invalidExports
            }

            exportSegments.append(contentsOf: refineExports)
        }

        logger.debug("Creating work package bundle")

        let imports = try await retrieveImportSegments(for: workPackage.value)
        let justifications = try await retrieveJustifications(for: workPackage.value)

        let bundle = WorkPackageBundle(
            workPackage: workPackage.value,
            extrinsics: extrinsics,
            importSegments: imports,
            justifications: justifications
        )

        logger.debug("Exporting work package bundle to data availability")

        let (erasureRoot, length) = try await dataAvailability.exportWorkpackageBundle(bundle: bundle)
        if erasureRoot == Data32() {
            throw GuaranteeingServiceError.dataAvailabilityError
        }

        logger.debug("Exporting segments to data availability", metadata: ["segmentCount": "\(exportSegments.count)"])

        let segmentRoot = try await dataAvailability.exportSegments(data: exportSegments, erasureRoot: erasureRoot)
        if segmentRoot == Data32() {
            throw GuaranteeingServiceError.dataAvailabilityError
        }

        logger.debug("Creating segments root mapping", metadata: ["segmentRoot": "\(segmentRoot)"])

        mappings.append(SegmentsRootMapping(workPackageHash: packageHash, segmentsRoot: segmentRoot))

        let packageSpecification = AvailabilitySpecifications(
            workPackageHash: packageHash,
            length: length,
            erasureRoot: erasureRoot,
            segmentRoot: segmentRoot,
            segmentCount: exportSegmentOffset
        )

        logger.debug("Building lookup dictionary from recent history")

        var oldLookups = [Data32: Data32]()
        for item in state.value.recentHistory.items {
            oldLookups.merge(item.lookup, uniquingKeysWith: { _, new in new })
        }

        logger.debug("Creating work report")

        let workReport = try WorkReport(
            authorizerHash: authorizerHash,
            coreIndex: UInt(coreIndex),
            authorizerTrace: authorizerTrace,
            refinementContext: workPackage.value.context,
            packageSpecification: packageSpecification,
            lookup: oldLookups,
            digests: ConfigLimitedSizeArray(config: config, array: workDigests),
            authGasUsed: UInt(authGasUsed.value)
        )

        workReportCache.write {
            $0[packageHash] = workReport
        }

        logger.debug("Work report created successfully", metadata: ["reportHash": "\(workReport.hash())"])

        return (bundle, mappings, workReport)
    }
}
