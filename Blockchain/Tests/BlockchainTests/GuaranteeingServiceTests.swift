@testable import Blockchain
import Foundation
import Testing
import TracingUtils
import Utils

struct GuaranteeingServiceTests {
    func setup(
        config: ProtocolConfigRef = .dev,
        time: TimeInterval = 988,
        keysCount: Int = 12,
    ) async throws -> BlockchainServices {
        await BlockchainServices(
            config: config,
            timeProvider: MockTimeProvider(time: time),
            keysCount: keysCount,
        )
    }

    @Test func onGenesis() async throws {
        let services = try await setup(keysCount: 1)
        let guaranteeingService = await services.guaranteeingService

        // Set up the signing key by triggering onBeforeEpoch
        let state = try await services.dataProvider.getBestState()
        let epoch = state.value.timeslot.timeslotToEpochIndex(config: services.config)

        // Create post state for the epoch
        let postState = SafrolePostState(
            timeslot: state.value.timeslot,
            entropyPool: state.value.entropyPool,
            previousValidators: state.value.previousValidators,
            currentValidators: state.value.currentValidators,
            nextValidators: state.value.nextValidators,
            validatorQueue: state.value.validatorQueue,
            ticketsAccumulator: state.value.safroleState.ticketsAccumulator,
            ticketsOrKeys: state.value.safroleState.ticketsOrKeys,
            ticketsVerifier: state.value.safroleState.ticketsVerifier,
        )

        await guaranteeingService.onBeforeEpoch(epoch: epoch, safroleState: postState)

        // Verify the signing key is properly set
        let publicKey = try DevKeyStore.getDevKey(seed: 0).ed25519
        let signingKey = try #require(guaranteeingService.signingKey.value)

        #expect(signingKey.0 == 0)
        #expect(signingKey.1.publicKey == publicKey)
    }

    @Test func onBeforeEpochWithMultipleValidators() async throws {
        let services = try await setup(keysCount: 3)
        let guaranteeingService = await services.guaranteeingService

        // Get state and create a safrole post state for testing
        let state = try await services.dataProvider.getBestState()

        var postState = SafrolePostState(
            timeslot: state.value.timeslot,
            entropyPool: state.value.entropyPool,
            previousValidators: state.value.previousValidators,
            currentValidators: state.value.currentValidators,
            nextValidators: state.value.nextValidators,
            validatorQueue: state.value.validatorQueue,
            ticketsAccumulator: state.value.safroleState.ticketsAccumulator,
            ticketsOrKeys: state.value.safroleState.ticketsOrKeys,
            ticketsVerifier: state.value.safroleState.ticketsVerifier,
        )

        let epoch = state.value.timeslot.timeslotToEpochIndex(config: services.config)
        await guaranteeingService.onBeforeEpoch(epoch: epoch, safroleState: postState)

        // Verify the signing key is set
        let firstSigningKey = guaranteeingService.signingKey.value
        #expect(firstSigningKey != nil)

        // Test with a different validator in the first position
        let secondValidator = postState.currentValidators.array[1]
        postState.currentValidators = try ConfigFixedSizeArray(
            config: services.config,
            array: [secondValidator] + postState.currentValidators.array.dropFirst().dropFirst() + [postState.currentValidators.array[0]],
        )

        await guaranteeingService.onBeforeEpoch(epoch: epoch, safroleState: postState)

        // Verify the signing key is updated to reflect the new validator order
        let secondSigningKey = guaranteeingService.signingKey.value
        #expect(secondSigningKey != nil)

        if firstSigningKey != nil, secondSigningKey != nil {
            #expect(try #require(secondSigningKey?.0) != firstSigningKey!.0)
        }
    }

    @Test func onBeforeEpochWithNoMatchingKeys() async throws {
        let services = try await setup(keysCount: 0)
        let guaranteeingService = await services.guaranteeingService

        // Get state and create post state
        let state = try await services.dataProvider.getBestState()
        let postState = SafrolePostState(
            timeslot: state.value.timeslot,
            entropyPool: state.value.entropyPool,
            previousValidators: state.value.previousValidators,
            currentValidators: state.value.currentValidators,
            nextValidators: state.value.nextValidators,
            validatorQueue: state.value.validatorQueue,
            ticketsAccumulator: state.value.safroleState.ticketsAccumulator,
            ticketsOrKeys: state.value.safroleState.ticketsOrKeys,
            ticketsVerifier: state.value.safroleState.ticketsVerifier,
        )

        let epoch = state.value.timeslot.timeslotToEpochIndex(config: services.config)
        await guaranteeingService.onBeforeEpoch(epoch: epoch, safroleState: postState)

        // Verify no signing key is set when there are no matching keys
        #expect(guaranteeingService.signingKey.value == nil)
    }

    // MARK: - Work Package Validation Tests

    @Test func testValidateSegmentsRootMapping() async throws {
        let services = try await setup()
        let guaranteeingService = await services.guaranteeingService

        // Create a work package for testing
        let workPackage = WorkPackage.dummy(config: services.config)

        // Create a valid mapping
        let validMapping = SegmentsRootMapping(
            workPackageHash: workPackage.hash(),
            segmentsRoot: Data32.random(),
        )

        // Test with invalid work package hash
        let invalidMapping = SegmentsRootMapping(
            workPackageHash: Data32.random(),
            segmentsRoot: Data32.random(),
        )

        // Test with empty segments root
        let emptyRootMapping = SegmentsRootMapping(
            workPackageHash: workPackage.hash(),
            segmentsRoot: Data32(),
        )

        try guaranteeingService.validateSegmentsRootMapping(validMapping, for: workPackage)
        // Expected to pass

        #expect(throws: GuaranteeingServiceError.segmentsRootNotFound) {
            try guaranteeingService.validateSegmentsRootMapping(invalidMapping, for: workPackage)
        }

        #expect(throws: GuaranteeingServiceError.segmentsRootNotFound) {
            try guaranteeingService.validateSegmentsRootMapping(emptyRootMapping, for: workPackage)
        }
    }

    // MARK: - Work Package Bundle Tests

    @Test func testValidateImportedSegments() async throws {
        let services = try await setup()
        let guaranteeingService = await services.guaranteeingService

        // Create a work package with import segments
        let workItem = WorkItem.dummy(config: services.config)
        var workItemWithImports = workItem
        workItemWithImports.inputs = [
            WorkItem.ImportedDataSegment(root: .segmentRoot(Data32.random()), index: 0),
            WorkItem.ImportedDataSegment(root: .workPackageHash(Data32.random()), index: 1),
        ]

        var workPackage = WorkPackage.dummy(config: services.config)

        workPackage.workItems = try ConfigLimitedSizeArray(
            config: services.config,
            array: [workItemWithImports],
        )

        // Create bundle with matching segment count
        let bundleWithCorrectSegments = WorkPackageBundle(
            workPackage: workPackage,
            extrinsics: [],
            importSegments: [Data4104(), Data4104()],
            justifications: [],
        )

        // Create bundle with mismatched segment count
        let bundleWithIncorrectSegments = WorkPackageBundle(
            workPackage: workPackage,
            extrinsics: [],
            importSegments: [Data4104()], // Only one segment
            justifications: [],
        )

        try guaranteeingService.validateImportedSegments(bundleWithCorrectSegments)
        // Expected to pass

        #expect(throws: GuaranteeingServiceError.invalidImportSegmentCount) {
            try guaranteeingService.validateImportedSegments(bundleWithIncorrectSegments)
        }
    }

    // MARK: - Work Report Processing Tests

    @Test func testWorkReportCache() async throws {
        let services = try await setup()
        let guaranteeingService = await services.guaranteeingService

        // Access the cache
        let initialCache = guaranteeingService.workReportCache.value
        #expect(initialCache.isEmpty)

        // Manually insert an item into the cache
        let mockReport = WorkReport.dummy(config: services.config)
        let mockHash = Data32.random()
        guaranteeingService.workReportCache.write { cache in
            cache[mockHash] = mockReport
        }

        // Verify it was stored
        let updatedCache = guaranteeingService.workReportCache.value
        #expect(updatedCache.count == 1)
        #expect(updatedCache[mockHash] == mockReport)
    }

    @Test func testProcessWorkPackageBundle() async throws {
        let services = try await setup(keysCount: 1)
        let guaranteeingService = await services.guaranteeingService

        // Set up the signing key
        let state = try await services.dataProvider.getBestState()
        let epoch = state.value.timeslot.timeslotToEpochIndex(config: services.config)
        let postState = SafrolePostState(
            timeslot: state.value.timeslot,
            entropyPool: state.value.entropyPool,
            previousValidators: state.value.previousValidators,
            currentValidators: state.value.currentValidators,
            nextValidators: state.value.nextValidators,
            validatorQueue: state.value.validatorQueue,
            ticketsAccumulator: state.value.safroleState.ticketsAccumulator,
            ticketsOrKeys: state.value.safroleState.ticketsOrKeys,
            ticketsVerifier: state.value.safroleState.ticketsVerifier,
        )

        await guaranteeingService.onBeforeEpoch(epoch: epoch, safroleState: postState)

        // Create a test bundle
        let workPackage = WorkPackage.dummy(config: services.config)
        let bundle = WorkPackageBundle(
            workPackage: workPackage,
            extrinsics: [],
            importSegments: [],
            justifications: [],
        )

        // Create valid mapping
        let mappings: SegmentsRootMappings = [
            SegmentsRootMapping(
                workPackageHash: workPackage.hash(),
                segmentsRoot: Data32.random(),
            ),
        ]

        // Test with invalid core index
        await #expect(throws: GuaranteeingServiceError.invalidCore) {
            _ = try await guaranteeingService.processWorkPackageBundle(
                coreIndex: CoreIndex.max,
                segmentsRootMappings: mappings,
                bundle: bundle,
            )
        }
    }

    // MARK: - Event Handling Tests

    @Test func handleWorkPackageBundleReceived() async throws {
        let services = try await setup(keysCount: 1)
        let guaranteeingService = await services.guaranteeingService
        let storeMiddleware = services.storeMiddleware

        // Set up the signing key
        let state = try await services.dataProvider.getBestState()
        let epoch = state.value.timeslot.timeslotToEpochIndex(config: services.config)
        let postState = SafrolePostState(
            timeslot: state.value.timeslot,
            entropyPool: state.value.entropyPool,
            previousValidators: state.value.previousValidators,
            currentValidators: state.value.currentValidators,
            nextValidators: state.value.nextValidators,
            validatorQueue: state.value.validatorQueue,
            ticketsAccumulator: state.value.safroleState.ticketsAccumulator,
            ticketsOrKeys: state.value.safroleState.ticketsOrKeys,
            ticketsVerifier: state.value.safroleState.ticketsVerifier,
        )

        await guaranteeingService.onBeforeEpoch(epoch: epoch, safroleState: postState)

        // Create a bundle
        let workPackage = WorkPackage.dummy(config: services.config)
        let bundle = WorkPackageBundle(
            workPackage: workPackage,
            extrinsics: [],
            importSegments: [],
            justifications: [],
        )

        // Create mappings
        let mappings: SegmentsRootMappings = [
            SegmentsRootMapping(
                workPackageHash: workPackage.hash(),
                segmentsRoot: Data32.random(),
            ),
        ]

        // Test handling a bundle event
        let event = RuntimeEvents.WorkPackageBundleReceived(
            coreIndex: 0,
            bundle: bundle,
            segmentsRootMappings: mappings,
        )

        await services.eventBus.publish(event)

        // Wait for event processing
        let events = await storeMiddleware.wait()

        // Expecting a response event
        let responseEvents = events.filter { $0 is RuntimeEvents.WorkPackageBundleReceivedResponse }
        #expect(responseEvents.count > 0)

        let responseEvent = try #require(responseEvents.first as? RuntimeEvents.WorkPackageBundleReceivedResponse)
        // This will often be an error result because the bundle validation is complex,
        // but we're just checking the event flow
        #expect(responseEvent.workBundleHash == bundle.hash())
    }
}
