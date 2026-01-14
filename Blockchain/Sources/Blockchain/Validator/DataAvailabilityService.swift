import Codec
import Foundation
import Networking
import Synchronization
import TracingUtils
import Utils

public enum DataAvailabilityError: Error {
    case storeError
    case retrievalError
    case erasureCodingError
    case distributionError
    case segmentNotFound
    case segmentsRootMappingNotFound
    case invalidSegmentIndex
    case invalidErasureRoot
    case invalidSegmentsRoot
    case invalidDataLength
    case pagedProofsGenerationError
    case invalidWorkReportSlot
    case invalidWorkReport
    case insufficientSignatures
    case invalidMerklePath
    case emptySegmentShards
    case invalidJustificationFormat
    case segmentsRootMismatch(calculated: Data32, expected: Data32)
    case invalidMetadata(String)
}

/// Data availability service for managing work reports and shard distribution
///
/// Refactored into focused modules for better maintainability.
/// This facade delegates to specialized services for different responsibilities.
///
/// Thread-safety: @unchecked Sendable is safe here because:
/// - Inherits safety from ServiceBase2 (immutable properties + ThreadSafeContainer)
/// - All properties are immutable (let), providing thread-safe access
public final class DataAvailabilityService: ServiceBase2, @unchecked Sendable, OnSyncCompleted {
    // MARK: - Properties

    private let dataProvider: BlockchainDataProvider
    private let dataStore: DataStore

    // Helper services (actors provide their own synchronization)
    private let shardManager: ShardManager
    private let availabilityVerification: AvailabilityVerification
    private let dataAvailabilityCleaner: DataAvailabilityCleaner
    private let networkRequestHelper: NetworkRequestHelper
    private let workReportProcessor: WorkReportProcessor
    private let shardDistributionManager: ShardDistributionManager
    private let assuranceCoordinator: AssuranceCoordinator

    // Expose dataStore for testing purposes
    public var testDataStore: DataStore { dataStore }

    // MARK: - Initialization

    public init(
        config: ProtocolConfigRef,
        eventBus: EventBus,
        scheduler: Scheduler,
        dataProvider: BlockchainDataProvider,
        dataStore: DataStore,
        erasureCodingDataStore: ErasureCodingDataStore? = nil,
        networkClient: AvailabilityNetworkClient? = nil
    ) async {
        self.dataProvider = dataProvider
        self.dataStore = dataStore
        self.networkClient = networkClient

        // Initialize helper services
        shardManager = ShardManager(erasureCodingDataStore: erasureCodingDataStore)
        availabilityVerification = AvailabilityVerification(dataStore: dataStore)
        dataAvailabilityCleaner = DataAvailabilityCleaner(erasureCodingDataStore: erasureCodingDataStore)
        networkRequestHelper = NetworkRequestHelper(
            dataProvider: dataProvider,
            networkClient: networkClient
        )
        workReportProcessor = WorkReportProcessor(
            dataStore: dataStore,
            erasureCodingDataStore: erasureCodingDataStore,
            config: config
        )
        shardDistributionManager = ShardDistributionManager(
            dataProvider: dataProvider,
            dataStore: dataStore,
            erasureCodingDataStore: erasureCodingDataStore,
            config: config
        )
        assuranceCoordinator = AssuranceCoordinator(
            dataProvider: dataProvider,
            config: config
        )

        super.init(id: "DataAvailability", config: config, eventBus: eventBus, scheduler: scheduler)

        // Schedule regular purging of old data
        scheduleForNextEpoch("DataAvailability.scheduleForNextEpoch") { [weak self] epoch in
            await self?.purge(epoch: epoch)
        }
    }

    /// Set the fetch strategy for network operations
    public func setFetchStrategy(_ strategy: FetchStrategy) async {
        await shardManager.setFetchStrategy(strategy)
    }

    public func onSyncCompleted() async {
        await subscribe(RuntimeEvents.WorkReportReceived.self, id: "DataAvailabilityService.WorkReportReceived") { [weak self] event in
            await self?.handleWorkReportReceived(event)
        }
        await subscribe(RuntimeEvents.ShardDistributionReceived.self,
                        id: "DataAvailabilityService.ShardDistributionReceived")
        { [weak self] event in
            await self?.handleShardDistributionReceived(event)
        }
        await subscribe(RuntimeEvents.AuditShardRequestReceived.self,
                        id: "DataAvailabilityService.AuditShardRequestReceived")
        { [weak self] event in
            await self?.handleAuditShardRequestReceived(event)
        }
        await subscribe(RuntimeEvents.SegmentShardRequestReceived.self,
                        id: "DataAvailabilityService.SegmentShardRequestReceived")
        { [weak self] event in
            await self?.handleSegmentShardRequestReceived(event)
        }
    }

    public func handleWorkReportReceived(_ event: RuntimeEvents.WorkReportReceived) async {
        let workReportHash = event.workReport.hash()
        do {
            try await shardDistributionManager.workReportDistribution(
                workReport: event.workReport,
                slot: event.slot,
                signatures: event.signatures
            )
            // Publish success response
            publish(RuntimeEvents.WorkReportReceivedResponse(
                workReportHash: workReportHash
            ))
        } catch {
            logger.error("Failed to handle work report: \(error)")
            // Publish error response so the protocol handler doesn't timeout
            publish(RuntimeEvents.WorkReportReceivedResponse(
                workReportHash: workReportHash,
                error: error
            ))
        }
    }

    public func handleShardDistributionReceived(_ event: RuntimeEvents.ShardDistributionReceived) async {
        let requestId = (try? event.generateRequestId()) ?? Data32()
        do {
            let (bundleShard, segmentShards, justification) = try await shardDistributionManager.shardDistribution(
                erasureRoot: event.erasureRoot,
                shardIndex: event.shardIndex
            )
            // Publish success response
            publish(RuntimeEvents.ShardDistributionReceivedResponse(
                requestId: requestId,
                bundleShard: bundleShard,
                segmentShards: segmentShards,
                justification: justification
            ))
        } catch {
            logger.error("Failed to handle shard distribution: \(error)")
            // Publish error response so the protocol handler doesn't timeout
            publish(RuntimeEvents.ShardDistributionReceivedResponse(
                requestId: requestId,
                error: error
            ))
        }
    }

    public func handleAuditShardRequestReceived(_ event: RuntimeEvents.AuditShardRequestReceived) async {
        let requestId = (try? event.generateRequestId()) ?? Data32()
        // For now, return an error response - this feature is not yet fully implemented
        let error = DataAvailabilityError.retrievalError
        logger.error("Failed to handle audit shard request: \(error)")
        // Publish error response so the protocol handler doesn't timeout
        publish(RuntimeEvents.AuditShardRequestReceivedResponse(
            requestId: requestId,
            error: error
        ))
    }

    public func handleSegmentShardRequestReceived(_ event: RuntimeEvents.SegmentShardRequestReceived) async {
        let requestId = (try? event.generateRequestId()) ?? Data32()
        // For now, return an error response - this feature is not yet fully implemented
        let error = DataAvailabilityError.retrievalError
        logger.error("Failed to handle segment shard request: \(error)")
        // Publish error response so the protocol handler doesn't timeout
        publish(RuntimeEvents.SegmentShardRequestReceivedResponse(
            requestId: requestId,
            error: error
        ))
    }

    /// Purge old data from the data availability stores
    /// - Parameter epoch: The current epoch index
    public func purge(epoch: EpochIndex) async {
        await dataAvailabilityCleaner.purge(epoch: epoch)
    }

    /// Get cleanup metrics
    /// - Returns: Cleanup metrics if ErasureCodingDataStore is available
    public func getCleanupMetrics() async -> CleanupMetrics? {
        await dataAvailabilityCleaner.getCleanupMetrics()
    }

    /// Reset cleanup metrics
    public func resetCleanupMetrics() async {
        await dataAvailabilityCleaner.resetCleanupMetrics()
    }

    // MARK: - Delegated Methods

    /// Fetch segments from data store
    public func fetchSegment(
        segments: [WorkItem.ImportedDataSegment],
        segmentsRootMappings: SegmentsRootMappings? = nil
    ) async throws -> [Data4104] {
        try await workReportProcessor.fetchSegment(
            segments: segments,
            segmentsRootMappings: segmentsRootMappings
        )
    }

    /// Export segments to import store
    public func exportSegments(data: [Data4104], erasureRoot: Data32) async throws -> Data32 {
        try await workReportProcessor.exportSegments(data: data, erasureRoot: erasureRoot)
    }

    /// Export a work package bundle to audit store
    public func exportWorkpackageBundle(bundle: WorkPackageBundle) async throws -> (erasureRoot: Data32, length: DataLength) {
        try await workReportProcessor.exportWorkpackageBundle(bundle: bundle)
    }

    /// Verify that a segment belongs to an erasure root
    public func verifySegment(segment: Data4104, index: UInt16, erasureRoot: Data32, proof: [Data32]) async -> Bool {
        await workReportProcessor.verifySegment(
            segment: segment,
            index: index,
            erasureRoot: erasureRoot,
            proof: proof
        )
    }

    /// Retrieve an audit bundle by erasure root
    public func retrieveAuditBundle(erasureRoot: Data32) async throws -> Data? {
        try await workReportProcessor.retrieveAuditBundle(erasureRoot: erasureRoot)
    }

    /// Reconstruct erasure-coded data from shards
    public func reconstructData(
        shards: [(index: UInt16, data: Data)],
        originalLength: Int
    ) async throws -> Data {
        try await workReportProcessor.reconstructData(
            shards: shards,
            originalLength: originalLength
        )
    }

    /// Reconstruct segments from erasure-coded shards
    public func reconstructSegments(
        shards: [(index: UInt16, data: Data)],
        segmentCount: Int
    ) async throws -> [Data4104] {
        try await workReportProcessor.reconstructSegments(
            shards: shards,
            segmentCount: segmentCount
        )
    }

    /// Fetch data from a specific validator
    public func fetchFromValidator(
        validator validatorIndex: ValidatorIndex,
        requestData: Data
    ) async throws -> Data {
        try await networkRequestHelper.fetchFromValidator(
            validator: validatorIndex,
            requestData: requestData
        )
    }

    /// Fetch shards from multiple validators concurrently
    public func fetchFromValidatorsConcurrently(
        validators validatorIndices: [ValidatorIndex],
        shardRequest: Data
    ) async throws -> [(validator: ValidatorIndex, data: Data)] {
        try await networkRequestHelper.fetchFromValidatorsConcurrently(
            validators: validatorIndices,
            shardRequest: shardRequest
        )
    }

    /// Work report distribution (CE 135)
    public func workReportDistribution(
        workReport: WorkReport,
        slot: UInt32,
        signatures: [ValidatorSignature]
    ) async {
        do {
            try await shardDistributionManager.workReportDistribution(
                workReport: workReport,
                slot: slot,
                signatures: signatures
            )
        } catch {
            logger.error("Failed to distribute work report: \(error)")
        }
    }

    /// Validate work report signatures
    public func validateWorkReportSignatures(
        signatures: [ValidatorSignature],
        workReportHash: Data32
    ) async throws {
        try await shardDistributionManager.validateWorkReportSignatures(
            signatures: signatures,
            workReportHash: workReportHash
        )
    }

    /// Shard distribution (CE 137)
    public func shardDistribution(
        erasureRoot: Data32,
        shardIndex: UInt16
    ) async throws {
        _ = try await shardDistributionManager.shardDistribution(
            erasureRoot: erasureRoot,
            shardIndex: shardIndex
        )
    }

    /// Request audit shards from validators (CE 138)
    public func requestAuditShards(
        workPackageHash: Data32,
        indices: [UInt16],
        validators: [ValidatorIndex]
    ) async throws -> [Data4104] {
        try await shardDistributionManager.requestAuditShards(
            workPackageHash: workPackageHash,
            indices: indices,
            validators: validators
        )
    }

    /// Handle incoming audit shard requests
    public func handleAuditShardRequest(
        workPackageHash: Data32,
        indices: [UInt16],
        requester: ValidatorIndex
    ) async throws -> [Data4104] {
        try await shardDistributionManager.handleAuditShardRequest(
            workPackageHash: workPackageHash,
            indices: indices,
            requester: requester
        )
    }

    /// Request segment shards from validators (CE 139/140)
    public func requestSegmentShards(
        segmentsRoot: Data32,
        indices: [UInt16],
        validators: [ValidatorIndex]
    ) async throws -> [Data4104] {
        try await shardDistributionManager.requestSegmentShards(
            segmentsRoot: segmentsRoot,
            indices: indices,
            validators: validators
        )
    }

    /// Handle incoming segment shard requests
    public func handleSegmentShardRequest(
        segmentsRoot: Data32,
        indices: [UInt16],
        requester: ValidatorIndex
    ) async throws -> [Data4104] {
        try await shardDistributionManager.handleSegmentShardRequest(
            segmentsRoot: segmentsRoot,
            indices: indices,
            requester: requester
        )
    }

    /// Distribute assurances to validators (CE 141)
    public func distributeAssurances(
        assurances: ExtrinsicAvailability.AssurancesList,
        parentHash: Data32,
        validators: [ValidatorIndex]
    ) async throws -> Bool {
        try await assuranceCoordinator.distributeAssurances(
            assurances: assurances,
            parentHash: parentHash,
            validators: validators
        )
    }

    /// Verify assurances from validators
    public func verifyAssurances(
        assurances: ExtrinsicAvailability.AssurancesList,
        parentHash: Data32
    ) async throws -> ExtrinsicAvailability.AssurancesList {
        try await assuranceCoordinator.verifyAssurances(
            assurances: assurances,
            parentHash: parentHash
        )
    }

    /// Verify that a work package is available
    public func isWorkPackageAvailable(workPackageHash: Data32) async -> Bool {
        await availabilityVerification.isWorkPackageAvailable(workPackageHash: workPackageHash)
    }

    /// Get the availability status of a work package
    public func getWorkPackageAvailabilityStatus(workPackageHash: Data32) async
        -> (available: Bool, segmentsRoot: Data32?, shardCount: Int?)
    {
        await availabilityVerification.getWorkPackageAvailabilityStatus(workPackageHash: workPackageHash)
    }

    /// Verify data availability for multiple work packages
    public func verifyMultipleWorkPackagesAvailability(
        workPackageHashes: [Data32]
    ) async -> [Data32: Bool] {
        await availabilityVerification.verifyMultipleWorkPackagesAvailability(
            workPackageHashes: workPackageHashes
        )
    }

    /// Retrieve a work package by hash
    public func retrieveWorkPackage(workPackageHash: Data32) async throws -> WorkPackage {
        try await workReportProcessor.retrieveWorkPackage(workPackageHash: workPackageHash)
    }

    /// Fetch work package from validators with network fallback
    public func fetchWorkPackageFromValidators(workPackageHash: Data32) async throws -> WorkPackage {
        try await workReportProcessor.fetchWorkPackageFromValidators(workPackageHash: workPackageHash)
    }

    /// Batch reconstruction with network fallback
    public func batchReconstructWithFallback(
        erasureRoots: [Data32],
        originalLengths: [Data32: Int]
    ) async throws -> [Data32: Data] {
        try await workReportProcessor.batchReconstructWithFallback(
            erasureRoots: erasureRoots,
            originalLengths: originalLengths
        )
    }

    /// Fetch segments with network fallback
    public func fetchSegmentsWithFallback(
        erasureRoot: Data32,
        indices: [Int],
        validators: [UInt16: NetAddr]? = nil
    ) async throws -> [Data4104] {
        try await workReportProcessor.fetchSegmentsWithFallback(
            erasureRoot: erasureRoot,
            indices: indices,
            validators: validators
        )
    }

    /// Get local shard count
    public func getLocalShardCount(erasureRoot: Data32) async -> Int {
        await shardManager.getLocalShardCount(erasureRoot: erasureRoot)
    }

    /// Calculate reconstruction potential
    public func canReconstruct(erasureRoot: Data32) async -> Bool {
        await shardManager.canReconstruct(erasureRoot: erasureRoot)
    }

    /// Get missing shard indices
    public func getMissingShardIndices(erasureRoot: Data32) async -> [UInt16] {
        await shardManager.getMissingShardIndices(erasureRoot: erasureRoot)
    }

    /// Get reconstruction plan
    public func getReconstructionPlan(erasureRoot: Data32) async -> ReconstructionPlan? {
        await shardManager.getReconstructionPlan(erasureRoot: erasureRoot)
    }

    /// Fetch segments with automatic reconstruction if needed
    public func fetchSegments(erasureRoot: Data32, indices: [Int]) async throws -> [Data4104] {
        try await shardManager.fetchSegments(erasureRoot: erasureRoot, indices: indices)
    }

    /// Reconstruct data from local shards
    public func reconstructFromLocalShards(erasureRoot: Data32, originalLength: Int) async throws -> Data {
        try await shardManager.reconstructFromLocalShards(
            erasureRoot: erasureRoot,
            originalLength: originalLength
        )
    }
}
