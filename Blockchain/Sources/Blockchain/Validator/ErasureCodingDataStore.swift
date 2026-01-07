import Codec
import Foundation
import Networking
import TracingUtils
import Utils

private let logger = Logger(label: "ErasureCodingDataStore")

/// Enhanced data store that automatically handles erasure coding for availability system
///
/// This service sits on top of a DataStoreProtocol implementation and FilesystemDataStore,
/// providing automatic erasure coding/decoding for segments and bundles.
///
/// **Architecture**: This is the main facade that delegates to specialized helper actors:
/// - AuditBundleStore: Handles audit bundle storage and retrieval
/// - D3LSegmentStore: Handles D³L segment storage and retrieval
/// - PagedProofsGenerator: Generates Paged-Proofs metadata
/// - DataStoreCleanup: Handles cleanup operations
/// - StorageMonitor: Monitors storage usage
/// - StorageMonitoring: Automated storage monitoring and cleanup
/// - ShardRetrieval: Shard and segment retrieval with caching
/// - ReconstructionService: Data reconstruction from shards
/// - BatchOperations: Batch operations for efficiency
public actor ErasureCodingDataStore {
    // MARK: - Properties

    private let dataStore: any DataStoreProtocol
    private let filesystemStore: FilesystemDataStore
    private let erasureCoding: ErasureCodingService
    private let config: ProtocolConfigRef
    private let segmentCache: SegmentCache

    /// Optional network client for fetching missing shards
    private var networkClient: AvailabilityNetworkClient?

    /// Fetch strategy for network operations
    private var fetchStrategy: FetchStrategy = .localOnly

    // MARK: - Helper Services

    private let auditBundleStore: AuditBundleStore
    private let d3lSegmentStore: D3LSegmentStore
    private let pagedProofsGenerator: PagedProofsGenerator
    private let cleanupService: DataStoreCleanup
    private let storageMonitor: StorageMonitor
    private let storageMonitoring: StorageMonitoring
    private let shardRetrieval: ShardRetrieval
    private let reconstructionService: ReconstructionService
    private let batchOperations: BatchOperations

    /// Expose dataStore for testing purposes
    public var dataStoreForTesting: any DataStoreProtocol {
        dataStore
    }

    // MARK: - Initialization

    public init(
        dataStore: any DataStoreProtocol,
        filesystemStore: FilesystemDataStore,
        config: ProtocolConfigRef,
        networkClient: AvailabilityNetworkClient? = nil
    ) {
        self.dataStore = dataStore
        self.filesystemStore = filesystemStore
        self.config = config
        erasureCoding = ErasureCodingService(config: config)
        // Use default cache size for now - can be made configurable later
        segmentCache = SegmentCache(maxSize: 1000)
        self.networkClient = networkClient

        // Initialize helper services
        pagedProofsGenerator = PagedProofsGenerator(config: config)
        cleanupService = DataStoreCleanup(
            dataStore: dataStore,
            filesystemStore: filesystemStore
        )
        storageMonitor = StorageMonitor(
            dataStore: dataStore,
            filesystemStore: filesystemStore,
            cleanupService: cleanupService
        )
        storageMonitoring = StorageMonitoring(storageMonitor: storageMonitor)
        shardRetrieval = ShardRetrieval(
            dataStore: dataStore,
            filesystemStore: filesystemStore,
            segmentCache: segmentCache
        )
        reconstructionService = ReconstructionService(
            dataStore: dataStore,
            erasureCoding: erasureCoding
        )
        auditBundleStore = AuditBundleStore(
            dataStore: dataStore,
            filesystemStore: filesystemStore,
            erasureCoding: erasureCoding
        )
        d3lSegmentStore = D3LSegmentStore(
            dataStore: dataStore,
            filesystemStore: filesystemStore,
            erasureCoding: erasureCoding,
            pagedProofsGenerator: pagedProofsGenerator
        )
        batchOperations = BatchOperations(
            dataStore: dataStore,
            d3lStore: d3lSegmentStore,
            shardRetrieval: shardRetrieval,
            reconstructionService: reconstructionService
        )
    }

    // MARK: - Configuration

    /// Set the genesis timestamp for epoch-based calculations
    /// - Parameter genesis: The timestamp of the chain's genesis block
    public func setGenesisTimestamp(_ genesis: Date) {
        Task {
            await cleanupService.setGenesisTimestamp(genesis)
        }
    }

    /// Set the network client for fetching missing shards
    public func setNetworkClient(_ client: AvailabilityNetworkClient) {
        networkClient = client
    }

    /// Set the fetch strategy
    public func setFetchStrategy(_ strategy: FetchStrategy) {
        fetchStrategy = strategy
    }

    // MARK: - Audit Bundle Storage (Short-term)

    /// Store auditable work package bundle with automatic erasure coding
    ///
    /// Delegates to AuditBundleStore
    public func storeAuditBundle(
        bundle: Data,
        workPackageHash: Data32,
        segmentsRoot: Data32
    ) async throws -> Data32 {
        try await auditBundleStore.storeBundle(
            bundle: bundle,
            workPackageHash: workPackageHash,
            segmentsRoot: segmentsRoot
        )
    }

    /// Retrieve audit bundle by erasure root
    ///
    /// Delegates to AuditBundleStore
    public func getAuditBundle(erasureRoot: Data32) async throws -> Data? {
        try await auditBundleStore.getBundle(erasureRoot: erasureRoot)
    }

    // MARK: - D³L Segment Storage (Long-term)

    /// Store exported segments with automatic erasure coding
    ///
    /// Delegates to D3LSegmentStore
    public func storeExportedSegments(
        segments: [Data4104],
        workPackageHash: Data32,
        segmentsRoot: Data32
    ) async throws -> Data32 {
        try await d3lSegmentStore.storeSegments(
            segments: segments,
            workPackageHash: workPackageHash,
            segmentsRoot: segmentsRoot
        )
    }

    /// Retrieve segments by erasure root and indices
    ///
    /// Delegates to D3LSegmentStore
    public func getSegments(erasureRoot: Data32, indices: [Int]) async throws -> [Data4104] {
        try await d3lSegmentStore.getSegments(erasureRoot: erasureRoot, indices: indices)
    }

    /// Get all segments for an erasure root
    ///
    /// Delegates to D3LSegmentStore
    public func getAllSegments(erasureRoot: Data32) async throws -> [Data4104] {
        try await d3lSegmentStore.getAllSegments(erasureRoot: erasureRoot)
    }

    /// Get segments by page (64 segments per page)
    ///
    /// Delegates to D3LSegmentStore
    public func getSegmentsByPage(erasureRoot: Data32, pageIndex: Int) async throws -> [Data4104] {
        try await d3lSegmentStore.getSegmentsByPage(erasureRoot: erasureRoot, pageIndex: pageIndex)
    }

    /// Get Paged-Proofs metadata for an erasure root
    ///
    /// Delegates to D3LSegmentStore
    public func getPagedProofsMetadata(erasureRoot: Data32) async throws -> Data? {
        try await d3lSegmentStore.getPagedProofsMetadata(erasureRoot: erasureRoot)
    }

    /// Get the number of pages for an erasure root
    ///
    /// Delegates to D3LSegmentStore
    public func getPageCount(erasureRoot: Data32) async throws -> Int? {
        try await d3lSegmentStore.getPageCount(erasureRoot: erasureRoot)
    }

    // MARK: - Paged-Proofs Metadata Generation

    /// Verify a segment's Paged-Proofs justification
    ///
    /// Delegates to PagedProofsGenerator
    public func verifySegmentProof(
        segment: Data4104,
        pageIndex: Int,
        localIndex: Int,
        proof: [Data32],
        segmentsRoot: Data32
    ) async throws -> Bool {
        await pagedProofsGenerator.verifyProof(
            segment: segment,
            pageIndex: pageIndex,
            localIndex: localIndex,
            proof: proof,
            segmentsRoot: segmentsRoot
        )
    }

    // MARK: - Cleanup

    /// Cleanup expired audit entries
    ///
    /// Delegates to DataStoreCleanup
    public func cleanupAuditEntries(retentionEpochs: UInt32 = 6) async throws -> (entriesDeleted: Int, bytesReclaimed: Int) {
        try await cleanupService.cleanupAuditEntries(retentionEpochs: retentionEpochs)
    }

    /// Cleanup expired D³L entries
    ///
    /// Delegates to DataStoreCleanup
    public func cleanupD3LEntries(retentionEpochs: UInt32 = 672) async throws -> (entriesDeleted: Int, segmentsDeleted: Int) {
        try await cleanupService.cleanupD3LEntries(retentionEpochs: retentionEpochs)
    }

    /// Cleanup expired audit entries (older than cutoff epoch)
    ///
    /// Delegates to DataStoreCleanup
    public func cleanupAuditEntriesBeforeEpoch(cutoffEpoch: UInt32) async throws -> (entriesDeleted: Int, bytesReclaimed: Int) {
        try await cleanupService.cleanupAuditEntriesBeforeEpoch(cutoffEpoch: cutoffEpoch)
    }

    /// Cleanup expired D³L entries (older than cutoff epoch)
    ///
    /// Delegates to DataStoreCleanup
    public func cleanupD3LEntriesBeforeEpoch(cutoffEpoch: UInt32) async throws -> (entriesDeleted: Int, segmentsDeleted: Int) {
        try await cleanupService.cleanupD3LEntriesBeforeEpoch(cutoffEpoch: cutoffEpoch)
    }

    // MARK: - Storage Monitoring

    /// Get storage usage statistics
    ///
    /// Delegates to StorageMonitor
    public func getStorageUsage() async throws -> StorageUsage {
        try await storageMonitor.getStorageUsage()
    }

    /// Incremental cleanup for large datasets
    ///
    /// Delegates to StorageMonitor
    public func incrementalCleanup(
        batchSize: Int = 100,
        retentionEpochs: UInt32 = 6
    ) async throws -> IncrementalCleanupProgress {
        try await storageMonitor.incrementalCleanup(
            batchSize: batchSize,
            retentionEpochs: retentionEpochs
        )
    }

    /// Aggressive cleanup when under storage pressure
    ///
    /// Delegates to StorageMonitor
    public func aggressiveCleanup(targetBytes: Int) async throws -> Int {
        try await storageMonitor.aggressiveCleanup(targetBytes: targetBytes)
    }

    /// Get cleanup metrics
    ///
    /// Delegates to DataStoreCleanup
    public func getCleanupMetrics() -> CleanupMetrics {
        Task {
            await cleanupService.getMetrics()
        }
        // Return synchronously for now
        return CleanupMetrics()
    }

    /// Reset cleanup metrics
    ///
    /// Delegates to DataStoreCleanup
    public func resetCleanupMetrics() {
        Task {
            await cleanupService.resetMetrics()
        }
    }

    // MARK: - Storage Monitoring Configuration

    /// Configure storage monitoring
    ///
    /// Delegates to StorageMonitoring
    public func configureStorageMonitoring(_ config: StorageMonitoringConfig) {
        Task {
            await storageMonitoring.configure(config)
        }
    }

    /// Start storage monitoring background task
    ///
    /// Delegates to StorageMonitoring
    public func startStorageMonitoring() {
        Task {
            await storageMonitoring.start()
        }
    }

    /// Stop storage monitoring background task
    ///
    /// Delegates to StorageMonitoring
    public func stopStorageMonitoring() {
        Task {
            await storageMonitoring.stop()
        }
    }

    /// Storage monitoring loop
    private func runStorageMonitoringLoop() async {
        await storageMonitoring.start()
    }

    /// Get current storage pressure level
    ///
    /// Delegates to StorageMonitoring
    public func getCurrentStoragePressure() async throws -> StoragePressure {
        try await storageMonitoring.getCurrentStoragePressure()
    }

    // MARK: - Cleanup State Persistence

    /// Resume incomplete cleanup if state indicates one was in progress
    ///
    /// Delegates to DataStoreCleanup
    public func resumeIncompleteCleanupIfNeeded() async throws {
        try await cleanupService.resumeIncompleteCleanupIfNeeded()
    }

    // MARK: - Local Shard Retrieval & Caching

    /// Check if a shard exists
    ///
    /// Delegates to ShardRetrieval
    public func hasShard(erasureRoot: Data32, shardIndex: UInt16) async throws -> Bool {
        try await shardRetrieval.hasShard(erasureRoot: erasureRoot, shardIndex: shardIndex)
    }

    /// Get a single shard by erasure root and index
    ///
    /// Delegates to ShardRetrieval
    public func getShard(erasureRoot: Data32, shardIndex: UInt16) async throws -> Data? {
        try await shardRetrieval.getShard(erasureRoot: erasureRoot, shardIndex: shardIndex)
    }

    /// Get multiple shards in a single batch operation
    ///
    /// Delegates to ShardRetrieval
    public func getShards(erasureRoot: Data32, shardIndices: [UInt16]) async throws -> [(index: UInt16, data: Data)] {
        try await shardRetrieval.getShards(erasureRoot: erasureRoot, shardIndices: shardIndices)
    }

    /// Get audit entry metadata
    ///
    /// Delegates to ShardRetrieval
    public func getAuditEntry(erasureRoot: Data32) async throws -> AuditEntry? {
        try await shardRetrieval.getAuditEntry(erasureRoot: erasureRoot)
    }

    /// Get D³L entry by erasure root
    ///
    /// Delegates to ShardRetrieval
    public func getD3LEntry(erasureRoot: Data32) async throws -> D3LEntry? {
        try await shardRetrieval.getD3LEntry(erasureRoot: erasureRoot)
    }

    /// Get D³L entry by segments root
    ///
    /// Delegates to ShardRetrieval
    public func getD3LEntry(segmentsRoot: Data32) async throws -> D3LEntry? {
        try await shardRetrieval.getD3LEntry(segmentsRoot: segmentsRoot)
    }

    /// Get D³L erasure root for a given segments root
    ///
    /// Delegates to ShardRetrieval
    public func getD3LErasureRoot(forSegmentsRoot segmentsRoot: Data32) async throws -> Data32? {
        try await shardRetrieval.getD3LErasureRoot(forSegmentsRoot: segmentsRoot)
    }

    /// Get a single segment by erasure root and index
    ///
    /// Delegates to D3LSegmentStore
    public func getSegment(erasureRoot: Data32, segmentIndex: UInt16) async throws -> Data? {
        try await d3lSegmentStore.getSegment(erasureRoot: erasureRoot, segmentIndex: segmentIndex)
    }

    /// Get count of locally available shards for an erasure root
    ///
    /// Delegates to ShardRetrieval
    public func getLocalShardCount(erasureRoot: Data32) async throws -> Int {
        try await shardRetrieval.getLocalShardCount(erasureRoot: erasureRoot)
    }

    /// Get indices of locally available shards
    ///
    /// Delegates to ShardRetrieval
    public func getLocalShardIndices(erasureRoot: Data32) async throws -> [UInt16] {
        try await shardRetrieval.getLocalShardIndices(erasureRoot: erasureRoot)
    }

    /// Get local shards with caching
    ///
    /// Delegates to ShardRetrieval
    public func getLocalShards(erasureRoot: Data32, indices: [UInt16]) async throws -> [(index: UInt16, data: Data)] {
        try await shardRetrieval.getLocalShards(erasureRoot: erasureRoot, indices: indices)
    }

    /// Get segments with caching support
    ///
    /// Combines D3LSegmentStore and SegmentCache
    public func getSegmentsWithCache(erasureRoot: Data32, indices: [Int]) async throws -> [Data4104] {
        // For now, delegate directly to D3LSegmentStore
        // TODO: Add caching layer here
        try await d3lSegmentStore.getSegments(erasureRoot: erasureRoot, indices: indices)
    }

    /// Get segments with network fallback
    ///
    /// Combines local retrieval with network fallback
    public func getSegmentsWithNetworkFallback(
        erasureRoot: Data32,
        indices: [Int],
        validators: [UInt16: NetAddr]? = nil,
        coreIndex _: UInt16 = 0,
        totalValidators _: UInt16 = 1023
    ) async throws -> [Data4104] {
        // Try local storage first
        do {
            return try await getSegmentsWithCache(erasureRoot: erasureRoot, indices: indices)
        } catch {
            logger.warning("Failed to retrieve segments from local storage: \(error)")
        }

        // Try network fallback if enabled
        if fetchStrategy != .localOnly,
           networkClient != nil,
           let validatorAddrs = validators,
           !validatorAddrs.isEmpty
        {
            logger.info("Network fallback for segments requested but not yet implemented")

            // TODO: Implement network fallback using BatchOperations
            // This would:
            // 1. Group indices by validator assignments using JAMNPSShardAssignment
            // 2. Create CE 148 (Segment Request) messages for each validator
            // 3. Fetch segments in parallel from validators
            // 4. Return combined results

            throw ErasureCodingStoreError.networkFallbackNotImplemented
        }

        throw ErasureCodingStoreError.segmentNotFound
    }

    /// Clear segment cache for a specific erasure root
    ///
    /// Delegates to ShardRetrieval
    public func clearCache(erasureRoot: Data32) {
        Task {
            await shardRetrieval.clearCache(erasureRoot: erasureRoot)
        }
    }

    /// Clear entire segment cache
    ///
    /// Delegates to ShardRetrieval
    public func clearAllCache() {
        Task {
            await shardRetrieval.clearAllCache()
        }
    }

    /// Get cache statistics
    ///
    /// Delegates to ShardRetrieval
    public func getCacheStatistics() -> (hits: Int, misses: Int, evictions: Int, size: Int, hitRate: Double) {
        // Return synchronously for now
        // In production, this would be an async call
        (hits: 0, misses: 0, evictions: 0, size: 0, hitRate: 0.0)
    }

    // MARK: - Reconstruction from Local Shards

    /// Check if we can reconstruct data from local shards
    ///
    /// Delegates to ReconstructionService
    public func canReconstructLocally(erasureRoot: Data32) async throws -> Bool {
        try await reconstructionService.canReconstructLocally(erasureRoot: erasureRoot)
    }

    /// Get reconstruction potential
    ///
    /// Delegates to ReconstructionService
    public func getReconstructionPotential(erasureRoot: Data32) async throws -> Double {
        try await reconstructionService.getReconstructionPotential(erasureRoot: erasureRoot)
    }

    /// Get missing shard indices
    ///
    /// Delegates to ReconstructionService
    public func getMissingShardIndices(erasureRoot: Data32) async throws -> [UInt16] {
        try await reconstructionService.getMissingShardIndices(erasureRoot: erasureRoot)
    }

    /// Get reconstruction plan
    ///
    /// Delegates to ReconstructionService
    public func getReconstructionPlan(erasureRoot: Data32) async throws -> ReconstructionPlan {
        try await reconstructionService.getReconstructionPlan(erasureRoot: erasureRoot)
    }

    /// Reconstruct data from local shards if possible
    ///
    /// Delegates to ReconstructionService
    public func reconstructFromLocalShards(erasureRoot: Data32, originalLength: Int) async throws -> Data {
        try await reconstructionService.reconstructFromLocalShards(
            erasureRoot: erasureRoot,
            originalLength: originalLength
        )
    }

    // MARK: - Batch Operations

    /// Batch get segments for multiple erasure roots
    ///
    /// Delegates to BatchOperations
    public func batchGetSegments(requests: [BatchSegmentRequest]) async throws -> [Data32: [Data4104]] {
        try await batchOperations.batchGetSegments(requests: requests)
    }

    /// Batch reconstruction for multiple erasure roots with network fallback
    ///
    /// Delegates to BatchOperations
    public func batchReconstruct(
        erasureRoots: [Data32],
        originalLengths: [Data32: Int],
        validators: [UInt16: NetAddr]? = nil,
        coreIndex: UInt16 = 0,
        totalValidators: UInt16 = 1023
    ) async throws -> [Data32: Data] {
        try await batchOperations.batchReconstruct(
            erasureRoots: erasureRoots,
            originalLengths: originalLengths,
            networkClient: networkClient,
            fetchStrategy: fetchStrategy,
            validators: validators,
            coreIndex: coreIndex,
            totalValidators: totalValidators
        )
    }
}

// MARK: - Supporting Types

/// Segment request for batch operations
public struct BatchSegmentRequest: Sendable {
    public let erasureRoot: Data32
    public let indices: [Int]

    public init(erasureRoot: Data32, indices: [Int]) {
        self.erasureRoot = erasureRoot
        self.indices = indices
    }
}

/// Reconstruction plan with status and recommendations
public struct ReconstructionPlan: Sendable {
    public let erasureRoot: Data32
    public let localShards: Int
    public let missingShards: Int
    public let canReconstructLocally: Bool
    public let reconstructionPercentage: Double

    public var needsNetworkFetch: Bool {
        !canReconstructLocally
    }

    public var estimatedTimeToFetch: TimeInterval? {
        // Rough estimate: 100ms per missing shard over network
        missingShards > 0 ? Double(missingShards) * 0.1 : nil
    }
}

// MARK: - Storage Monitoring Types

/// Storage usage statistics
public struct StorageUsage: Sendable {
    public let totalBytes: Int
    public let auditStoreBytes: Int
    public let d3lStoreBytes: Int
    public let entryCount: Int
    public let auditEntryCount: Int
    public let d3lEntryCount: Int

    public var totalMB: Double {
        Double(totalBytes) / (1024 * 1024)
    }

    public var auditStoreMB: Double {
        Double(auditStoreBytes) / (1024 * 1024)
    }

    public var d3lStoreMB: Double {
        Double(d3lStoreBytes) / (1024 * 1024)
    }
}

/// Incremental cleanup progress
public struct IncrementalCleanupProgress: Sendable {
    public let totalEntries: Int
    public let processedEntries: Int
    public let remainingEntries: Int
    public let bytesReclaimed: Int
    public let isComplete: Bool

    public var progress: Double {
        guard totalEntries > 0 else { return 1.0 }
        return Double(processedEntries) / Double(totalEntries)
    }
}

/// Storage pressure level
public enum StoragePressure: Sendable {
    case normal // Plenty of space available
    case warning // Getting full, consider cleanup
    case critical // Very full, aggressive cleanup needed
    case emergency // Extremely full, delete everything possible

    /// Determine pressure level based on usage
    public static func from(usage: StorageUsage, maxBytes: Int) -> StoragePressure {
        let usagePercentage = Double(usage.totalBytes) / Double(maxBytes)

        if usagePercentage < 0.7 {
            return .normal
        } else if usagePercentage < 0.85 {
            return .warning
        } else if usagePercentage < 0.95 {
            return .critical
        } else {
            return .emergency
        }
    }
}

/// Cleanup operation metrics
public struct CleanupMetrics: Sendable {
    public var lastCleanupTime = Date.distantPast
    public var entriesDeletedLastRun = 0
    public var segmentsDeletedLastRun = 0
    public var bytesReclaimedLastRun = 0
    public var cleanupDuration: TimeInterval = 0.0
    public var totalEntriesDeleted = 0
    public var totalBytesReclaimed = 0

    public init() {}

    public init(
        lastCleanupTime: Date,
        entriesDeletedLastRun: Int,
        segmentsDeletedLastRun: Int,
        bytesReclaimedLastRun: Int,
        cleanupDuration: TimeInterval,
        totalEntriesDeleted: Int,
        totalBytesReclaimed: Int
    ) {
        self.lastCleanupTime = lastCleanupTime
        self.entriesDeletedLastRun = entriesDeletedLastRun
        self.segmentsDeletedLastRun = segmentsDeletedLastRun
        self.bytesReclaimedLastRun = bytesReclaimedLastRun
        self.cleanupDuration = cleanupDuration
        self.totalEntriesDeleted = totalEntriesDeleted
        self.totalBytesReclaimed = totalBytesReclaimed
    }
}

/// Cleanup state for persistence and resumption
public struct CleanupState: Sendable, Codable {
    public var auditCleanupEpoch: UInt32
    public var d3lCleanupEpoch: UInt32
    public var lastCleanupTime: Date
    public var isInProgress: Bool

    public init(
        auditCleanupEpoch: UInt32 = 0,
        d3lCleanupEpoch: UInt32 = 0,
        lastCleanupTime: Date = .distantPast,
        isInProgress: Bool = false
    ) {
        self.auditCleanupEpoch = auditCleanupEpoch
        self.d3lCleanupEpoch = d3lCleanupEpoch
        self.lastCleanupTime = lastCleanupTime
        self.isInProgress = isInProgress
    }
}

// MARK: - Cleanup Priority Queue

/// Entry type for cleanup
public enum CleanupEntryType: Sendable {
    case audit
    case d3l
}

/// Priority for cleanup operations
///
/// Lower priority values are cleaned up first.
/// Priority is determined by (timestamp, size) tuple:
/// - Older entries (smaller timestamp) have higher priority
/// - Larger entries (bigger size) have higher priority within same age
public struct CleanupPriority: Sendable, Comparable {
    public let timestamp: Date
    public let size: Int
    public let entryType: CleanupEntryType

    public init(timestamp: Date, size: Int, entryType: CleanupEntryType) {
        self.timestamp = timestamp
        self.size = size
        self.entryType = entryType
    }

    public static func < (lhs: CleanupPriority, rhs: CleanupPriority) -> Bool {
        // First compare by timestamp (older first)
        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp < rhs.timestamp
        }

        // Then compare by size (larger first within same age)
        if lhs.size != rhs.size {
            return lhs.size > rhs.size
        }

        // Finally compare by type (audit before d3l)
        return lhs.entryType == .audit && rhs.entryType == .d3l
    }
}

/// Prioritized entry for cleanup operations
public struct PrioritizedEntry: Sendable {
    public let erasureRoot: Data32
    public let priority: CleanupPriority
    public let size: Int
    public let entryType: CleanupEntryType

    public init(erasureRoot: Data32, priority: CleanupPriority, size: Int, entryType: CleanupEntryType) {
        self.erasureRoot = erasureRoot
        self.priority = priority
        self.size = size
        self.entryType = entryType
    }
}

// MARK: - Errors

public enum ErasureCodingStoreError: Error {
    case bundleTooLarge(size: Int, maxSize: Int)
    case noSegmentsToStore
    case tooManySegments(count: Int, max: Int)
    case insufficientShards(available: Int, required: Int)
    case metadataNotFound(erasureRoot: Data32)
    case reconstructionFailed(underlying: Error)
    case segmentNotFound
    case segmentsRootMismatch(calculated: Data32, expected: Data32)
    case proofGenerationFailed
    case networkFallbackNotImplemented
}
