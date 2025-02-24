import Foundation
import Synchronization
import TracingUtils
import Utils

public enum GuaranteeingServiceError: Error {
    case noAuthorizerHash
    case invalidExports
}

struct GuaranteeingAuthorizationFunction: IsAuthorizedFunction {}
struct GuaranteeingRefineInvocation: RefineInvocation {}

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
    ) async throws -> (Data32, Data) {
        // 1. Perform basic verification
        guard try validateWorkPackageBundle(bundle, segmentsRootMappings: segmentsRootMappings) else {
            throw WorkPackageError.invalidBundle
        }

        // 2. Execute refine logic
        let workReportHash = try await refineWorkPackageBundle(bundle)

        // 3. Sign the work report hash
        let signature = try await signData(workReportHash)

        return (workReportHash, signature)
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

    private func refineWorkPackageBundle(_: WorkPackageBundle) async throws -> Data32 {
        // TODO: Implement refine logic here
        // For example, execute the work items and generate a work report
        // let workReportHash = try await refineLogic.execute(bundle)
        Data32()
    }

    private func signData(_: Data32) async throws -> Data {
        // TODO: Implement signing logic here
        // For example, use the guarantor's private key to sign the data
        // let signature = try await keystore.sign(data: data, with: privateKey)
        Data()
    }
}

public final class GuaranteeingService: ServiceBase2, @unchecked Sendable {
    private let dataProvider: BlockchainDataProvider
    private let keystore: KeyStore
    private let dataAvailability: DataAvailability

    private let authorizationFunction: IsAuthorizedFunction
    private let refineInvocation: RefineInvocation

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

        authorizationFunction = GuaranteeingAuthorizationFunction()
        refineInvocation = GuaranteeingRefineInvocation()

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
        try await refine(coreIndex: event.coreIndex, package: event.workPackageRef, extrinsics: event.extrinsics)
    }

    private func refine(coreIndex: CoreIndex, package: WorkPackageRef, extrinsics: [Data]) async throws {
        guard let (validatorIndex, signingKey) = signingKey.value else {
            logger.debug("not in current validator set, skipping refine")
            return
        }
        try await shareWorkPackage(coreIndex: coreIndex, workPackage: package.value, extrinsics: extrinsics)

        let workReport = try await createWorkReport(for: package, coreIndex: coreIndex)
        let payload = SigningContext.guarantee + workReport.hash().data
        let signature = try signingKey.sign(message: payload)
        let event = RuntimeEvents.WorkReportGenerated(item: workReport, signature: signature)
        publish(event)
    }

    public func createWorkPackageBundle(_ workPackage: WorkPackage, extrinsics: [Data]) async throws -> WorkPackageBundle {
        // 1. Retrieve the necessary data for the bundle
        let importSegments = try await retrieveImportSegments(for: workPackage)
        let justifications = try await retrieveJustifications(for: workPackage)

        // 2. Construct the work package bundle
        return WorkPackageBundle(
            workPackage: workPackage,
            extrinsic: extrinsics,
            importSegments: importSegments,
            justifications: justifications
        )
    }

    public func retrieveSegmentsRootMappings(for workPackage: WorkPackage) async throws -> SegmentsRootMappings {
        // 1. Get the import segments from the work package
        let importSegments = try await retrieveImportSegments(for: workPackage)

        // 2. Map work-package hashes to segments-roots
        var mappings: SegmentsRootMappings = []
        for segment in importSegments {
            // 2.1. Get the work-package hash from the segment ??
            let workPackageHash = workPackage.hash()

            // 2.2. Retrieve the segments-root from the blockchain or data availability layer
            let segmentsRoot = try await retrieveSegmentsRoot(for: workPackageHash)

            // 2.3. Create a mapping and add it to the array
            let mapping = SegmentsRootMapping(workPackageHash: workPackageHash, segmentsRoot: segmentsRoot)
            mappings.append(mapping)
        }

        return mappings
    }

    private func retrieveSegmentsRoot(for _: Data32) async throws -> SegmentsRoot {
        // 1. Query the blockchain or data availability layer to get the segments-root
        // For example, use a blockchain data provider to fetch the segments-root
        // let segmentsRoot = try await dataProvider.getSegmentsRoot(for: workPackageHash)
        let segmentsRoot = SegmentsRoot()
        // 2. If the segments-root is not found, throw an error
        // guard let segmentsRoot = segmentsRoot else {
        //    throw WorkPackageError.segmentsRootNotFound
        // }

        return segmentsRoot
    }

    // Work Package Sharing (Send Side)
    public func shareWorkPackage(coreIndex: CoreIndex, workPackage: WorkPackage, extrinsics: [Data]) async throws {
        // 1. Get other guarantors assigned to the same core, how to
        let guarantors = try await getGuarantors(for: coreIndex)

        // 2. Validate the work package
        guard try validate(workPackage: workPackage) else {
            logger.error("Invalid work package: \(workPackage)")
            throw WorkPackageError.invalidWorkPackage
        }
        // 3. Create WorkPackageBundle

        let bundle = try await createWorkPackageBundle(workPackage, extrinsics: extrinsics)

        // 4. TODO: Send the bundle to other guarantors
        // 5. Map work-package hashes to segments-roots
        var mappings: SegmentsRootMappings = []
        for guarantor in guarantors {
            let (workReportHash, signature) = try await guarantor.receiveWorkPackageBundle(
                coreIndex: coreIndex,
                segmentsRootMappings: mappings,
                bundle: bundle
            )

            // 6. Publish the work report hash and signature
            // let event = RuntimeEvents.WorkReportGenerated(hash: workReportHash, signature: signature)
            // publish(event)
        }
    }

    public func getGuarantors(for coreIndex: CoreIndex) async throws -> [Guarantor] {
        // 1. Get the current blockchain state
        let state = try await dataProvider.getState(hash: dataProvider.bestHead.hash)

        // 2. Get the core assignment for the current timeslot
        let coreAssignment: [CoreIndex] = state.value.getCoreAssignment(
            config: config,
            randomness: state.value.entropyPool.t2,
            timeslot: state.value.timeslot
        )

        // 3. Ensure the core index is valid
        guard coreIndex < coreAssignment.count else {
            logger.error("Invalid core index: \(coreIndex)")
            try throwUnreachable("invalid validator index/core assignment")
        }

        // 4. Get the validator index assigned to the core
        let validatorIndex = coreAssignment[Int(coreIndex)]

        let validator = state.value.currentValidators[Int(validatorIndex)]
        // 5. Create a Guarantor object for the validator
        let guarantor = Guarantor(
            id: validator.ed25519.blake2b256hash(), // Use the validator's public key hash as the ID
            coreIndex: coreIndex
        )

        return [guarantor]
    }

    private func validate(workPackage _: WorkPackage) throws -> Bool {
        // TODO: Add validate func
        true
    }

    private func retrieveExtrinsicData(for _: WorkPackage) async throws -> [Data] {
        // TODO: Implement retrieveExtrinsicData
        // Implement logic to retrieve extrinsic data associated with the work package
        // For example, fetch from the blockchain or local storage
        [] // Placeholder
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
    private func createWorkReport(for workPackage: WorkPackageRef, coreIndex: CoreIndex) async throws -> WorkReport {
        let state = try await dataProvider.getState(hash: dataProvider.bestHead.hash)
        let packageHash = workPackage.hash
        let corePool = state.value.coreAuthorizationPool[coreIndex]
        let authorizerHash = try corePool.array.first.unwrap(orError: GuaranteeingServiceError.noAuthorizerHash)
        var exportSegmentOffset: UInt16 = 0
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
                // RefineInvocation invoke up data to workresult
                let refineRes = try await refineInvocation
                    .invoke(
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

            let (erasureRoot, length) = try await dataAvailability.exportWorkpackageBundle(bundle: WorkPackageBundle(
                workPackage: workPackage.value,
                extrinsic: [], // TODO: get extrinsic data
                importSegments: [],
                justifications: []
            ))

            let segmentRoot = try await dataAvailability.exportSegments(data: exportSegments, erasureRoot: erasureRoot)

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
            return try WorkReport(
                authorizerHash: authorizerHash,
                coreIndex: coreIndex,
                authorizationOutput: authorizationOutput,
                refinementContext: workPackage.value.context,
                packageSpecification: packageSpecification,
                lookup: oldLookups,
                results: ConfigLimitedSizeArray(config: config, array: workResults)
            )

        case let .failure(error):
            logger.error("Authorization failed with error: \(error)")
            throw error
        }
    }
}
