import Codec
import Foundation
import Synchronization
import TracingUtils
import Utils

/**
 * Errors that can occur in the GuaranteeingService.
 */
public enum GuaranteeingServiceError: Error, Equatable {
    /// No authorizer hash found in the core authorization pool
    case noAuthorizerHash
    /// The number of exported segments doesn't match the expected count
    case invalidExports
    /// The work package validation failed
    case invalidWorkPackage
    /// The work package bundle validation failed
    case invalidBundle
    /// The segments root was not found in the mappings
    case segmentsRootNotFound
    /// The node is not a validator
    case notValidator
    /// The core assignment is invalid
    case invalidCore
    /// Unable to get enough signatures from other validators
    case unableToGetSignatures
    /// The work package authorization failed
    case authorizationError(WorkResultError)
    /// Unable to retrieve imported segments
    case importSegmentsNotFound
    /// The number of imported segments doesn't match the expected count
    case invalidImportSegmentCount
    /// Failed to export segments to data availability
    case dataAvailabilityError
    /// The service account for a work item does not exist
    case serviceAccountNotFound
}

public final class GuaranteeingService: ServiceBase2, @unchecked Sendable, OnBeforeEpoch, OnSyncCompleted {
    private let dataProvider: BlockchainDataProvider
    private let keystore: KeyStore
    private let dataAvailability: DataAvailability

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

    /**
     * Validates a work package bundle and its associated segments root mappings.
     *
     * @param bundle The work package bundle to validate
     * @param segmentsRootMappings The mappings of work package hashes to segment roots
     * @return True if the bundle is valid, false otherwise
     */
    func validateWorkPackageBundle(
        _ bundle: WorkPackageBundle,
        segmentsRootMappings: SegmentsRootMappings
    ) async throws {
        // First validate the work package itself
        try validate(workPackage: bundle.workPackage)

        // Validate the work package authorization
        try await validateAuthorization(bundle.workPackage)

        // Validate the segments-root mappings
        for mapping in segmentsRootMappings {
            try validateSegmentsRootMapping(mapping, for: bundle.workPackage)
        }

        // Validate imported segments match the declared inputs
        try validateImportedSegments(bundle)
    }

    /**
     * Validates that the imported segments in a bundle match the work items' input declarations.
     *
     * @param bundle The work package bundle to validate
     * @return True if the imported segments are valid, false otherwise
     */
    func validateImportedSegments(_ bundle: WorkPackageBundle) throws {
        // Collect all imported segment references from work items
        let importSegmentCount = bundle.workPackage.workItems.array.flatMap(\.inputs).count

        // Verify we have the correct number of imported segments
        if bundle.importSegments.count != importSegmentCount {
            logger.debug("Import segment count mismatch",
                         metadata: ["expected": "\(importSegmentCount)", "actual": "\(bundle.importSegments.count)"])
            throw GuaranteeingServiceError.invalidImportSegmentCount
        }

        // Additional validation of segment content could be implemented here
    }

    /**
     * Processes a work package bundle to create a work report.
     * This is the core function that validates, processes, and generates a work report from a bundle.
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

        // Check if we've already processed this bundle
        let workPackageHash = bundle.workPackage.hash()
        if let cachedReport = workReportCache.value[workPackageHash] {
            logger.debug("Using cached work report for bundle", metadata: ["workPackageHash": "\(workPackageHash)"])
            return cachedReport
        }

        let state = try await dataProvider.getState(hash: dataProvider.bestHead.hash)

        // Get current core assignments
        let coreAssignment = getCoreAssignment(state: state)

        // Verify the validator is assigned to the specified core
        guard let currentCoreIndex = coreAssignment[safe: Int(validatorIndex)] else {
            try throwUnreachable("invalid validator index/core assignment")
        }
        guard currentCoreIndex == coreIndex else {
            logger.error("Invalid core assignment",
                         metadata: ["expectedCore": "\(currentCoreIndex)", "actualCore": "\(coreIndex)"])
            throw GuaranteeingServiceError.invalidCore
        }

        // Get the workPackage reference
        let workPackage = bundle.workPackage.asRef()

        // Validate the bundle
        try await validateWorkPackageBundle(bundle, segmentsRootMappings: segmentsRootMappings)

        // Process the work package bundle and create a work report
        let (_, _, workReport) = try await createWorkReport(
            state: state,
            coreIndex: coreIndex,
            workPackage: workPackage,
            extrinsics: bundle.extrinsics,
            segmentsRootMappings: segmentsRootMappings
        )

        // Cache the work report for future use
        var cacheValue = workReportCache.value
        cacheValue[workPackageHash] = workReport
        workReportCache.value = cacheValue

        return workReport
    }

    /**
     * Processes a work package by refining it, generating a work report, collecting signatures,
     * and distributing the final work report.
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

        // Validate the work package
        try validate(workPackage: workPackage.value)

        // Generate the work report, bundle, and mappings
        let (bundle, mappings, workReport) = try await createWorkReport(
            state: state,
            coreIndex: coreIndex,
            workPackage: workPackage,
            extrinsics: extrinsics,
            segmentsRootMappings: nil
        )

        let workReportHash = workReport.hash()

        // Find other validators assigned to the same core
        var otherValidators = [(ValidatorIndex, Ed25519PublicKey)]()

        // Get the validators for the current epoch
        let currentValidators = state.value.currentValidators
        for (idx, core) in coreAssignment.enumerated() {
            if core == coreIndex, idx != Int(validatorIndex) {
                otherValidators.append((ValidatorIndex(idx), currentValidators.array[idx].ed25519))
            }
        }

        logger.debug("Requesting signatures from validators",
                     metadata: ["validatorCount": "\(otherValidators.count)", "coreIndex": "\(coreIndex)"])

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

        logger.info("Generated work report",
                    metadata: ["reportHash": "\(workReportHash)", "timeslot": "\(timeslot)", "signatures": "\(sigs.count)"])

        // Distribute the guaranteed work-report to all current validators
        publish(RuntimeEvents.WorkReportGenerated(
            workReport: workReport,
            slot: timeslot,
            signatures: sigs
        ))
    }

    /**
     * Gets the core assignment for the current timeslot.
     *
     * @param state The current state
     * @return An array of core indices assigned to validators
     */
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
     * @param mapping The mapping to validate
     * @param for The work package the mapping is for
     * @return True if the mapping is valid, false otherwise
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
     * @param workPackage The work package to validate
     * @return True if the authorization is valid, false otherwise
     */
    func validateAuthorization(_ workPackage: WorkPackage) async throws {
        // Get the current state
        let head = await dataProvider.bestHead
        let state = try await dataProvider.getState(hash: head.hash)

        // Verify the service account exists
        guard let serviceAccount = state.value.serviceAccount(index: workPackage.authorizationServiceIndex) else {
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
     * 2. The service accounts exist and are authorized
     * 3. The gas limits are within bounds
     * 4. The refinement context is valid
     *
     * @param workPackage The work package to validate
     * @return True if the work package is valid, false otherwise
     */
    func validate(workPackage: WorkPackage) throws {
        // Basic validation checks
        guard !workPackage.workItems.array.isEmpty else {
            logger.debug("Work package has no work items")
            throw GuaranteeingServiceError.invalidWorkPackage
        }

        // Validate max gas usage
        var totalGas = Gas(0)
        for item in workPackage.workItems {
            totalGas += item.refineGasLimit

            // Check gas limits
            let maxWorkItemRefineGas = Gas(1_000_000_000) // Default maximum refine gas
            guard item.refineGasLimit <= maxWorkItemRefineGas else {
                logger.debug("Work item refine gas exceeds limit",
                             metadata: ["actual": "\(item.refineGasLimit)", "limit": "\(maxWorkItemRefineGas)"])
                throw GuaranteeingServiceError.invalidWorkPackage
            }

            let maxWorkItemAccumulateGas = Gas(1_000_000) // Default maximum accumulate gas
            guard item.accumulateGasLimit <= maxWorkItemAccumulateGas else {
                logger.debug("Work item accumulate gas exceeds limit",
                             metadata: ["actual": "\(item.accumulateGasLimit)", "limit": "\(maxWorkItemAccumulateGas)"])
                throw GuaranteeingServiceError.invalidWorkPackage
            }
        }

        // Check total gas usage
        let maxWorkPackageTotalGas = Gas(5_000_000_000) // Default maximum total gas
        guard totalGas <= maxWorkPackageTotalGas else {
            logger.debug("Work package total gas exceeds limit",
                         metadata: ["actual": "\(totalGas)", "limit": "\(maxWorkPackageTotalGas)"])
            throw GuaranteeingServiceError.invalidWorkPackage
        }

        // Validate the refinement context
        let context = workPackage.context
        let maxPrerequisiteWorkPackages = 8 // Default maximum prerequisite work packages
        guard context.prerequisiteWorkPackages.count <= maxPrerequisiteWorkPackages else {
            logger.debug("Too many prerequisite work packages",
                         metadata: ["count": "\(context.prerequisiteWorkPackages.count)",
                                    "limit": "\(maxPrerequisiteWorkPackages)"])
            throw GuaranteeingServiceError.invalidWorkPackage
        }
    }

    /**
     * Retrieves imported segments for a work package.
     *
     * @param for The work package to retrieve segments for
     * @return An array of data segments
     */
    func retrieveImportSegments(for workPackage: WorkPackage) async throws -> [Data4104] {
        var segments = [Data4104]()

        // Collect all import segment references from work items
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
     * @param for The work package to retrieve justifications for
     * @return An array of justification data
     */
    func retrieveJustifications(for workPackage: WorkPackage) async throws -> [Data] {
        var justifications = [Data]()

        // Collect all import segment references from work items
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
            // Get the imports and justifications
            let imports = try await retrieveImportSegments(for: workPackage.value)
            let justifications = try await retrieveJustifications(for: workPackage.value)

            // Create the bundle
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

        // Get the authorizer hash from the core pool
        let corePool = state.value.coreAuthorizationPool[coreIndex]
        guard let authorizerHash = corePool.array.first else {
            logger.error("No authorizer hash found for core", metadata: ["coreIndex": "\(coreIndex)"])
            throw GuaranteeingServiceError.noAuthorizerHash
        }

        var exportSegmentOffset: UInt16 = 0
        var mappings: SegmentsRootMappings = []

        // Run the authorization check
        logger.debug("Authorizing work package", metadata: ["workPackageHash": "\(packageHash)"])
        let res = try await isAuthorized(config: config, serviceAccounts: state.value, package: workPackage.value, coreIndex: coreIndex)
        let authorizationOutput = try res.0.mapError(GuaranteeingServiceError.authorizationError).get()
        logger.debug("Work package authorized successfully", metadata: ["outputSize": "\(authorizationOutput.count)"])

        var workResults = [WorkResult]()
        var exportSegments = [Data4104]()

        // Fetch import segments for refinement
        var importSegments = [[Data4104]]()
        for item in workPackage.value.workItems {
            let segment = try await dataAvailability.fetchSegment(segments: item.inputs, segmentsRootMappings: segmentsRootMappings)
            importSegments.append(segment)
        }

        logger.debug("Processing work items", metadata: ["itemCount": "\(workPackage.value.workItems.count)"])

        // Process each work item
        for (i, item) in workPackage.value.workItems.enumerated() {
            logger.debug("Refining work item",
                         metadata: ["itemIndex": "\(i)", "serviceIndex": "\(item.serviceIndex)"])

            // Execute the refine operation to get work result
            let refineRes = try await refine(
                config: config,
                serviceAccounts: state.value,
                workItemIndex: i,
                workPackage: workPackage.value,
                authorizerOutput: authorizationOutput,
                importSegments: importSegments,
                exportSegmentOffset: UInt64(exportSegmentOffset)
            )

            // Update export segment offset
            exportSegmentOffset += item.outputDataSegmentsCount
            let workResult = WorkResult(
                serviceIndex: item.serviceIndex,
                codeHash: workPackage.value.authorizationCodeHash,
                payloadHash: item.payloadBlob.blake2b256hash(),
                gasRatio: item.refineGasLimit,
                output: WorkOutput(refineRes.result),
                gasUsed: item.accumulateGasLimit,
                importsCount: UInt32(item.inputs.count),
                exportsCount: UInt32(item.outputDataSegmentsCount),
                extrinsicsCount: UInt32(item.outputs.count),
                extrinsicSize: UInt32(item.outputs.reduce(into: 0) { $0 += $1.length })
            )
            workResults.append(workResult)

            // Validate the number of exported segments matches what was declared
            guard item.outputDataSegmentsCount == refineRes.exports.count else {
                logger.error("Export segment count mismatch",
                             metadata: ["expected": "\(item.outputDataSegmentsCount)", "actual": "\(refineRes.exports.count)"])
                throw GuaranteeingServiceError.invalidExports
            }

            exportSegments.append(contentsOf: refineRes.exports)
        }

        logger.debug("Creating work package bundle")

        // Get the imports and justifications
        let imports = try await retrieveImportSegments(for: workPackage.value)
        let justifications = try await retrieveJustifications(for: workPackage.value)

        // Create the work package bundle
        let bundle = WorkPackageBundle(
            workPackage: workPackage.value,
            extrinsics: extrinsics,
            importSegments: imports,
            justifications: justifications
        )

        logger.debug("Exporting work package bundle to data availability")

        // Export the bundle to data availability
        // This will erasure-code and distribute the bundle to the audit store
        // as per GP 14.3.1
        logger.debug("Exporting work package bundle to data availability")
        let (erasureRoot, length) = try await dataAvailability.exportWorkpackageBundle(bundle: bundle)
        if erasureRoot == Data32() {
            throw GuaranteeingServiceError.dataAvailabilityError
        }

        logger.debug("Exporting segments to data availability", metadata: ["segmentCount": "\(exportSegments.count)"])

        // Export the segments to data availability
        // This will store the segments in the long-term imports store
        // as per GP 14.3.1
        let segmentRoot = try await dataAvailability.exportSegments(data: exportSegments, erasureRoot: erasureRoot)
        if segmentRoot == Data32() {
            throw GuaranteeingServiceError.dataAvailabilityError
        }

        logger.debug("Creating segments root mapping", metadata: ["segmentRoot": "\(segmentRoot)"])

        // Add the mapping
        mappings.append(SegmentsRootMapping(workPackageHash: packageHash, segmentsRoot: segmentRoot))

        // Create the availability specifications as per GP 14.4.1
        let packageSpecification = AvailabilitySpecifications(
            workPackageHash: packageHash,
            length: length,
            erasureRoot: erasureRoot,
            segmentRoot: segmentRoot,
            segmentCount: exportSegmentOffset
        )

        logger.debug("Building lookup dictionary from recent history")

        // Build the lookup dictionary from recent history
        var oldLookups = [Data32: Data32]()
        for item in state.value.recentHistory.items {
            oldLookups.merge(item.lookup, uniquingKeysWith: { _, new in new })
        }

        logger.debug("Creating work report")

        // Create the work report
        let workReport = try WorkReport(
            authorizerHash: authorizerHash,
            coreIndex: coreIndex,
            authorizationOutput: authorizationOutput,
            refinementContext: workPackage.value.context,
            packageSpecification: packageSpecification,
            lookup: oldLookups,
            results: ConfigLimitedSizeArray(config: config, array: workResults)
        )

        // Cache the work report
        workReportCache.write {
            $0[packageHash] = workReport
        }

        logger.debug("Work report created successfully", metadata: ["reportHash": "\(workReport.hash())"])

        return (bundle, mappings, workReport)
    }
}
