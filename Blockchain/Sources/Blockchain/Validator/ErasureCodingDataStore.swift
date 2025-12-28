import Codec
import Foundation
import Networking
import TracingUtils
import Utils

private let logger = Logger(label: "ErasureCodingDataStore")
private let cEcOriginalCount = 342

/// Actor for thread-safe counters
private actor Counter {
    private var value: Int = 0
    func increment() -> Int { value += 1; return value }
    func add(_ delta: Int) -> Int { value += delta; return value }
    func get() -> Int { value }
}

/// Enhanced data store that automatically handles erasure coding for availability system
///
/// This service sits on top of a DataStoreProtocol implementation and FilesystemDataStore,
/// providing automatic erasure coding/decoding for segments and bundles.
public actor ErasureCodingDataStore {
    private let dataStore: any DataStoreProtocol
    private let filesystemStore: FilesystemDataStore
    private let erasureCoding: ErasureCodingService
    private let config: ProtocolConfigRef
    private let segmentCache: SegmentCache

    /// Optional network client for fetching missing shards
    private var networkClient: AvailabilityNetworkClient?

    /// Fetch strategy for network operations
    private var fetchStrategy: FetchStrategy = .localOnly

    /// Cleanup metrics tracking
    private var cleanupMetrics = CleanupMetrics()

    /// Cleanup state for persistence and resumption
    private var cleanupState = CleanupState()

    /// Expose dataStore for testing purposes
    public var dataStoreForTesting: any DataStoreProtocol {
        dataStore
    }

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
    /// Per GP 14.3.1: Stores work-package + extrinsics + imports + proofs
    /// - Erasure-codes the bundle into 1,023 shards
    /// - Stores in filesystem under audit/ directory
    /// - Records metadata in RocksDB
    /// - Sets timestamp for retention tracking (6 epochs)
    ///
    /// - Parameters:
    ///   - bundle: Complete auditable work package data
    ///   - workPackageHash: Hash of the work package
    ///   - segmentsRoot: Merkle root of segments
    /// - Returns: Erasure root for the stored bundle
    public func storeAuditBundle(
        bundle: Data,
        workPackageHash: Data32,
        segmentsRoot: Data32
    ) async throws -> Data32 {
        logger.debug("Storing audit bundle: workPackageHash=\(workPackageHash.toHexString()), size=\(bundle.count)")

        // Validate bundle size (GP spec: max ~13.6 MB)
        let maxBundleSize = 13_791_360 // From GP spec
        guard bundle.count <= maxBundleSize else {
            throw ErasureCodingStoreError.bundleTooLarge(size: bundle.count, maxSize: maxBundleSize)
        }

        // Erasure-code the bundle
        let shards = try await erasureCoding.encodeBlob(bundle)

        // Calculate erasure root
        let erasureRoot = try await erasureCoding.calculateErasureRoot(
            segmentsRoot: segmentsRoot,
            shards: shards
        )

        // Store bundle in filesystem (for quick retrieval)
        try await filesystemStore.storeAuditBundle(erasureRoot: erasureRoot, data: bundle)

        // Store shards in RocksDB (for distributed access)
        let shardTuples = shards.enumerated().map { index, data in
            (index: UInt16(index), data: data)
        }
        try await dataStore.storeShards(shards: shardTuples, erasureRoot: erasureRoot)

        // Store metadata
        try await dataStore.setTimestamp(erasureRoot: erasureRoot, timestamp: Date())
        try await dataStore.setAuditEntry(
            workPackageHash: workPackageHash,
            erasureRoot: erasureRoot,
            bundleSize: bundle.count,
            timestamp: Date()
        )
        try await dataStore.set(erasureRoot: erasureRoot, forSegmentRoot: segmentsRoot)

        logger.info("Stored audit bundle: erasureRoot=\(erasureRoot.toHexString())")

        return erasureRoot
    }

    /// Retrieve audit bundle by erasure root
    ///
    /// - Parameter erasureRoot: Erasure root identifying the bundle
    /// - Returns: Bundle data or nil if not found
    public func getAuditBundle(erasureRoot: Data32) async throws -> Data? {
        // Try filesystem first (faster)
        if let bundle = try await filesystemStore.getAuditBundle(erasureRoot: erasureRoot) {
            return bundle
        }

        // Fallback to reconstruction from shards
        let indices = try await dataStore.getAvailableShardIndices(erasureRoot: erasureRoot)
        guard indices.count >= cEcOriginalCount else {
            logger.warning("Insufficient shards for reconstruction: \(indices.count)/\(cEcOriginalCount)")
            return nil
        }

        let shards = try await dataStore.getShards(erasureRoot: erasureRoot, shardIndices: Array(indices.prefix(cEcOriginalCount)))

        // Determine original size from audit metadata
        guard let auditEntry = try await dataStore.getAuditEntry(erasureRoot: erasureRoot) else {
            return nil
        }

        // Reconstruct
        let reconstructed = try await erasureCoding.reconstruct(
            shards: shards,
            originalLength: auditEntry.bundleSize
        )

        logger.debug("Reconstructed audit bundle from \(shards.count) shards")

        return reconstructed
    }

    // MARK: - D³L Segment Storage (Long-term)

    /// Store exported segments with automatic erasure coding
    ///
    /// Per GP spec: Stores exported segments with Paged-Proofs metadata
    /// - Erasure-codes each segment individually (4,104 bytes → 1,023 shards of 12 bytes)
    /// - Stores shards in filesystem under d3l/ directory
    /// - Generates and stores Paged-Proofs metadata
    /// - Sets timestamp for retention tracking (672 epochs = 28 days)
    ///
    /// - Parameters:
    ///   - segments: Array of exported segments (4,104 bytes each)
    ///   - workPackageHash: Hash of the work package
    ///   - segmentsRoot: Merkle root of the segments
    /// - Returns: Erasure root for the stored segments
    public func storeExportedSegments(
        segments: [Data4104],
        workPackageHash: Data32,
        segmentsRoot: Data32
    ) async throws -> Data32 {
        guard !segments.isEmpty else {
            throw ErasureCodingStoreError.noSegmentsToStore
        }

        // Validate segment count (GP spec: max 3,072)
        guard segments.count <= 3072 else {
            throw ErasureCodingStoreError.tooManySegments(count: segments.count, max: 3072)
        }

        logger.debug("Storing \(segments.count) exported segments: workPackageHash=\(workPackageHash.toHexString())")

        // Calculate segments root Merkle tree
        let calculatedSegmentsRoot = Merklization.binaryMerklize(segments.map(\.data))
        guard calculatedSegmentsRoot == segmentsRoot else {
            throw ErasureCodingStoreError.segmentsRootMismatch(
                calculated: calculatedSegmentsRoot,
                expected: segmentsRoot
            )
        }

        // Generate Paged-Proofs metadata
        let pagedProofsMetadata = try generatePagedProofsMetadata(segments: segments)

        // Encode all segments together
        let shards = try await erasureCoding.encodeSegments(segments)

        // Calculate erasure root
        let erasureRoot = try await erasureCoding.calculateErasureRoot(
            segmentsRoot: segmentsRoot,
            shards: shards
        )

        // Store each shard's individual data
        for (index, shard) in shards.enumerated() {
            try await filesystemStore.storeD3LShard(
                erasureRoot: erasureRoot,
                shardIndex: UInt16(index),
                data: shard
            )
        }

        // Store metadata
        try await dataStore.setTimestamp(erasureRoot: erasureRoot, timestamp: Date())
        try await dataStore.setPagedProofsMetadata(erasureRoot: erasureRoot, metadata: pagedProofsMetadata)
        try await dataStore.setD3LEntry(
            segmentsRoot: segmentsRoot,
            erasureRoot: erasureRoot,
            segmentCount: UInt32(segments.count),
            timestamp: Date()
        )
        try await dataStore.set(segmentRoot: segmentsRoot, forWorkPackageHash: workPackageHash)
        try await dataStore.set(erasureRoot: erasureRoot, forSegmentRoot: segmentsRoot)

        logger.info("Stored exported segments: erasureRoot=\(erasureRoot.toHexString()), count=\(segments.count)")

        return erasureRoot
    }

    /// Retrieve segments by erasure root and indices
    ///
    /// - Parameters:
    ///   - erasureRoot: Erasure root identifying the segments
    ///   - indices: Array of segment indices to retrieve (0-based)
    /// - Returns: Array of retrieved segments
    public func getSegments(erasureRoot: Data32, indices: [Int]) async throws -> [Data4104] {
        guard !indices.isEmpty else {
            return []
        }

        logger.debug("Retrieving \(indices.count) segments from erasureRoot=\(erasureRoot.toHexString())")

        // Try to get available shard indices
        let availableShardIndices = try await dataStore.getAvailableShardIndices(erasureRoot: erasureRoot)

        // Check if we can reconstruct
        guard availableShardIndices.count >= cEcOriginalCount else {
            throw ErasureCodingStoreError.insufficientShards(
                available: availableShardIndices.count,
                required: cEcOriginalCount
            )
        }

        // Get shards for reconstruction
        let shardTuples = try await dataStore.getShards(
            erasureRoot: erasureRoot,
            shardIndices: Array(availableShardIndices.prefix(cEcOriginalCount))
        )

        // Get segment count from metadata
        guard let d3lEntry = try await dataStore.getD3LEntry(erasureRoot: erasureRoot) else {
            throw ErasureCodingStoreError.metadataNotFound(erasureRoot: erasureRoot)
        }

        let segmentCount = Int(d3lEntry.segmentCount)
        let originalLength = segmentCount * 4104

        // Reconstruct segments
        let reconstructedData = try await erasureCoding.reconstruct(
            shards: shardTuples,
            originalLength: originalLength
        )

        // Split into individual segments
        var result: [Data4104] = []
        for index in indices {
            guard index < segmentCount else {
                continue
            }

            let start = index * 4104
            let end = min(start + 4104, reconstructedData.count)
            let segmentData = Data(reconstructedData[start ..< end])

            guard let segment = Data4104(segmentData) else {
                continue
            }

            result.append(segment)
        }

        logger.debug("Retrieved \(result.count)/\(indices.count) segments")

        return result
    }

    /// Get all segments for an erasure root
    ///
    /// - Parameter erasureRoot: Erasure root identifying the segments
    /// - Returns: Array of all segments
    public func getAllSegments(erasureRoot: Data32) async throws -> [Data4104] {
        guard let d3lEntry = try await dataStore.getD3LEntry(erasureRoot: erasureRoot) else {
            return []
        }

        let segmentCount = Int(d3lEntry.segmentCount)
        let indices = Array(0 ..< segmentCount)

        return try await getSegments(erasureRoot: erasureRoot, indices: indices)
    }

    /// Get segments by page (64 segments per page)
    ///
    /// - Parameters:
    ///   - erasureRoot: Erasure root identifying the segments
    ///   - pageIndex: Page index to retrieve
    /// - Returns: Array of segments in the page
    public func getSegmentsByPage(erasureRoot: Data32, pageIndex: Int) async throws -> [Data4104] {
        guard let d3lEntry = try await dataStore.getD3LEntry(erasureRoot: erasureRoot) else {
            throw ErasureCodingStoreError.metadataNotFound(erasureRoot: erasureRoot)
        }

        let segmentCount = Int(d3lEntry.segmentCount)
        let pageSize = 64

        let startIdx = pageIndex * pageSize
        guard startIdx < segmentCount else {
            return []
        }

        let endIdx = min(startIdx + pageSize, segmentCount)
        let indices = Array(startIdx ..< endIdx)

        return try await getSegments(erasureRoot: erasureRoot, indices: indices)
    }

    /// Get Paged-Proofs metadata for an erasure root
    ///
    /// - Parameter erasureRoot: Erasure root identifying the segments
    /// - Returns: Paged-Proofs metadata, or nil if not found
    public func getPagedProofsMetadata(erasureRoot: Data32) async throws -> Data? {
        try await dataStore.getPagedProofsMetadata(erasureRoot: erasureRoot)
    }

    /// Get the number of pages for an erasure root
    ///
    /// - Parameter erasureRoot: Erasure root identifying the segments
    /// - Returns: Number of pages, or nil if not found
    public func getPageCount(erasureRoot: Data32) async throws -> Int? {
        guard let d3lEntry = try await dataStore.getD3LEntry(erasureRoot: erasureRoot) else {
            return nil
        }

        let segmentCount = Int(d3lEntry.segmentCount)
        let pageSize = 64
        return (segmentCount + pageSize - 1) / pageSize
    }

    // MARK: - Paged-Proofs Metadata Generation

    /// Generate Paged-Proofs metadata for exported segments
    ///
    /// Per GP spec (work_packages_and_reports.tex eq:pagedproofs):
    /// Groups segments into pages of 64, generates Merkle justification paths
    /// and subtree pages for efficient segment justification
    ///
    /// - Parameter segments: Array of exported segments
    /// - Returns: Paged-Proofs metadata as Data
    private func generatePagedProofsMetadata(segments: [Data4104]) throws -> Data {
        guard !segments.isEmpty else {
            return Data()
        }

        // Per GP spec: Page size is 64 segments
        let pageSize = 64
        let pageCount = (segments.count + pageSize - 1) / pageSize

        // Calculate the segments root (constant-depth Merkle tree)
        let segmentsRoot = Merklization.constantDepthMerklize(segments.map(\.data))

        var pages: [Data] = []

        for pageIndex in 0 ..< pageCount {
            let startIdx = pageIndex * pageSize
            let endIdx = min(startIdx + pageSize, segments.count)
            let pageSegments = Array(segments[startIdx ..< endIdx])

            // For each page, generate:
            // 1. Merkle justification paths for each segment in the page (depth 6)
            // 2. Merkle subtree page for the page

            let pageMetadata = try generatePageMetadata(
                pageSegments: pageSegments,
                pageIndex: pageIndex,
                segmentsRoot: segmentsRoot,
                totalSegments: segments.count
            )

            pages.append(pageMetadata)
        }

        // Encode pages using JamEncoder
        let encoded = try JamEncoder.encode(pageCount, segmentsRoot, pages)

        logger.debug("Generated Paged-Proofs metadata: \(pageCount) pages, \(segments.count) segments")

        return encoded
    }

    /// Generate metadata for a single page of segments
    ///
    /// - Parameters:
    ///   - pageSegments: Segments in this page
    ///   - pageIndex: Index of the page
    ///   - segmentsRoot: Root of all segments
    ///   - totalSegments: Total number of segments
    /// - Returns: Page metadata as Data
    private func generatePageMetadata(
        pageSegments: [Data4104],
        pageIndex: Int,
        segmentsRoot _: Data32,
        totalSegments _: Int
    ) throws -> Data {
        // Per GP spec: depth 6 for 64 segments per page
        let merkleDepth: UInt8 = 6

        // For each segment in the page, generate its Merkle justification path
        var justificationPaths: [[Data32]] = []
        for (localIndex, segment) in pageSegments.enumerated() {
            let globalIndex = pageIndex * 64 + localIndex

            // Generate Merkle proof path from segment to root
            let path = Merklization.trace(
                pageSegments.map(\.data),
                index: localIndex,
                hasher: Blake2b256.self
            )

            // Convert PathElements to Data32 hashes
            var pathHashes: [Data32] = []
            for element in path {
                switch element {
                case let .left(data):
                    // Convert Data to Data32
                    guard let hash = Data32(data) else {
                        throw ErasureCodingStoreError.proofGenerationFailed
                    }
                    pathHashes.append(hash)
                case let .right(hash):
                    pathHashes.append(hash)
                }
            }

            justificationPaths.append(pathHashes)
        }

        // Calculate the Merkle subtree page for this page
        // This is a Merkle tree of the 64 segments in the page
        let pageHashes = pageSegments.map { $0.data.blake2b256hash() }
        let subtreeRoot = Merklization.binaryMerklize(pageHashes.map(\.data))

        // Encode page metadata:
        // - Merkle depth (6)
        // - Justification paths for each segment
        // - Subtree root
        let encoded = try JamEncoder.encode(
            merkleDepth,
            justificationPaths.count,
            justificationPaths,
            subtreeRoot
        )

        return encoded
    }

    /// Verify a segment's Paged-Proofs justification
    ///
    /// - Parameters:
    ///   - segment: The segment to verify
    ///   - pageIndex: Page containing the segment
    ///   - localIndex: Index within the page
    ///   - proof: Merkle proof path
    ///   - segmentsRoot: Expected root
    /// - Returns: True if the segment is valid
    public func verifySegmentProof(
        segment: Data4104,
        pageIndex _: Int,
        localIndex: Int,
        proof: [Data32],
        segmentsRoot: Data32
    ) async throws -> Bool {
        // Calculate segment hash
        let segmentHash = segment.data.blake2b256hash()

        // Start with segment hash
        var currentValue = segmentHash
        var currentIndex = localIndex

        // Traverse the Merkle proof
        for (level, proofElement) in proof.enumerated() {
            // At each level, combine current value with proof element
            let bitSet = (currentIndex >> level) & 1

            if bitSet == 0 {
                // Current value is on the left
                let combined = currentValue.data + proofElement.data
                currentValue = combined.blake2b256hash()
            } else {
                // Current value is on the right
                let combined = proofElement.data + currentValue.data
                currentValue = combined.blake2b256hash()
            }
        }

        // Final value should match segmentsRoot
        return currentValue == segmentsRoot
    }

    // MARK: - Cleanup

    /// Cleanup expired audit entries (older than retention period)
    ///
    /// Uses iterator-based cleanup to avoid loading all entries into memory.
    ///
    /// - Parameter retentionEpochs: Number of epochs to retain (default: 6)
    public func cleanupAuditEntries(retentionEpochs: UInt32 = 6) async throws -> (entriesDeleted: Int, bytesReclaimed: Int) {
        let epochDuration: TimeInterval = 600 // 10 minutes per epoch (GP spec)
        let cutoffDate = Date().addingTimeInterval(-TimeInterval(retentionEpochs) * epochDuration)

        let deletedCount = Counter()
        let bytesReclaimed = Counter()

        // Use iterator-based cleanup to process entries in batches
        _ = try await dataStore.cleanupAuditEntriesIteratively(
            before: cutoffDate,
            batchSize: 100
        ) { batch in
            for entry in batch {
                // Delete from filesystem
                try await filesystemStore.deleteAuditBundle(erasureRoot: entry.erasureRoot)

                // Delete from RocksDB
                try await dataStore.deleteAuditEntry(erasureRoot: entry.erasureRoot)
                try await dataStore.deleteShards(erasureRoot: entry.erasureRoot)

                _ = await deletedCount.increment()
                _ = await bytesReclaimed.add(entry.bundleSize)
            }
        }

        let finalDeletedCount = await deletedCount.get()
        let finalBytesReclaimed = await bytesReclaimed.get()

        logger.info("Cleanup: deleted \(finalDeletedCount) audit entries, reclaimed \(finalBytesReclaimed) bytes")

        return (finalDeletedCount, finalBytesReclaimed)
    }

    /// Cleanup expired D³L entries (older than retention period)
    ///
    /// Uses iterator-based cleanup to avoid loading all entries into memory.
    ///
    /// - Parameter retentionEpochs: Number of epochs to retain (default: 672)
    public func cleanupD3LEntries(retentionEpochs: UInt32 = 672) async throws -> (entriesDeleted: Int, segmentsDeleted: Int) {
        let epochDuration: TimeInterval = 600 // 10 minutes per epoch
        let cutoffDate = Date().addingTimeInterval(-TimeInterval(retentionEpochs) * epochDuration)

        let deletedEntries = Counter()
        let deletedSegments = Counter()

        // Use iterator-based cleanup to process entries in batches
        _ = try await dataStore.cleanupD3LEntriesIteratively(
            before: cutoffDate,
            batchSize: 100
        ) { batch in
            for entry in batch {
                // Delete from filesystem
                try await filesystemStore.deleteD3LShards(erasureRoot: entry.erasureRoot)

                // Delete from RocksDB
                try await dataStore.deleteD3LEntry(erasureRoot: entry.erasureRoot)
                try await dataStore.deleteShards(erasureRoot: entry.erasureRoot)

                _ = await deletedEntries.increment()
                _ = await deletedSegments.add(Int(entry.segmentCount))
            }
        }

        let finalDeletedEntries = await deletedEntries.get()
        let finalDeletedSegments = await deletedSegments.get()

        logger.info("Cleanup: deleted \(finalDeletedEntries) D³L entries, \(finalDeletedSegments) segments")

        return (finalDeletedEntries, finalDeletedSegments)
    }

    /// Cleanup expired audit entries (older than cutoff epoch)
    ///
    /// - Parameter cutoffEpoch: Cleanup entries from epochs before this value
    /// - Returns: Tuple of (entries deleted, bytes reclaimed)
    public func cleanupAuditEntriesBeforeEpoch(cutoffEpoch: UInt32) async throws -> (entriesDeleted: Int, bytesReclaimed: Int) {
        let startTime = Date()
        let cutoffDate = epochToTimestamp(epoch: cutoffEpoch)

        // Save state before starting cleanup
        cleanupState.auditCleanupEpoch = cutoffEpoch
        cleanupState.isInProgress = true
        cleanupState.lastCleanupTime = startTime
        try await saveCleanupState()

        let entries = try await dataStore.listAuditEntries(before: cutoffDate)

        var deletedCount = 0
        var bytesReclaimed = 0

        for entry in entries {
            // Delete from filesystem
            try await filesystemStore.deleteAuditBundle(erasureRoot: entry.erasureRoot)

            // Delete from RocksDB
            try await dataStore.deleteAuditEntry(erasureRoot: entry.erasureRoot)
            try await dataStore.deleteShards(erasureRoot: entry.erasureRoot)

            deletedCount += 1
            bytesReclaimed += entry.bundleSize
        }

        let duration = Date().timeIntervalSince(startTime)

        // Update metrics
        cleanupMetrics.lastCleanupTime = Date()
        cleanupMetrics.entriesDeletedLastRun = deletedCount
        cleanupMetrics.bytesReclaimedLastRun = bytesReclaimed
        cleanupMetrics.cleanupDuration = duration
        cleanupMetrics.totalEntriesDeleted += deletedCount
        cleanupMetrics.totalBytesReclaimed += bytesReclaimed

        // Mark cleanup as complete
        cleanupState.isInProgress = false
        try await saveCleanupState()

        logger.info(
            "Cleanup: deleted \(deletedCount) audit entries before epoch \(cutoffEpoch), reclaimed \(bytesReclaimed) bytes in \(duration)s"
        )

        return (deletedCount, bytesReclaimed)
    }

    /// Cleanup expired D³L entries (older than cutoff epoch)
    ///
    /// - Parameter cutoffEpoch: Cleanup entries from epochs before this value
    /// - Returns: Tuple of (entries deleted, segments deleted)
    public func cleanupD3LEntriesBeforeEpoch(cutoffEpoch: UInt32) async throws -> (entriesDeleted: Int, segmentsDeleted: Int) {
        let startTime = Date()
        let cutoffDate = epochToTimestamp(epoch: cutoffEpoch)

        // Save state before starting cleanup
        cleanupState.d3lCleanupEpoch = cutoffEpoch
        cleanupState.isInProgress = true
        cleanupState.lastCleanupTime = startTime
        try await saveCleanupState()

        let entries = try await dataStore.listD3LEntries(before: cutoffDate)

        var deletedEntries = 0
        var deletedSegments = 0

        for entry in entries {
            // Delete from filesystem
            try await filesystemStore.deleteD3LShards(erasureRoot: entry.erasureRoot)

            // Delete from RocksDB
            try await dataStore.deleteD3LEntry(erasureRoot: entry.erasureRoot)
            try await dataStore.deleteShards(erasureRoot: entry.erasureRoot)

            deletedEntries += 1
            deletedSegments += Int(entry.segmentCount)
        }

        let duration = Date().timeIntervalSince(startTime)

        // Update metrics
        cleanupMetrics.lastCleanupTime = Date()
        cleanupMetrics.entriesDeletedLastRun += deletedEntries
        cleanupMetrics.segmentsDeletedLastRun = deletedSegments
        cleanupMetrics.cleanupDuration += duration
        cleanupMetrics.totalEntriesDeleted += deletedEntries

        // Mark cleanup as complete
        cleanupState.isInProgress = false
        try await saveCleanupState()

        logger.info(
            "Cleanup: deleted \(deletedEntries) D³L entries before epoch \(cutoffEpoch), \(deletedSegments) segments in \(duration)s"
        )

        return (deletedEntries, deletedSegments)
    }

    /// Convert epoch index to timestamp
    /// - Parameter epoch: The epoch index to convert
    /// - Returns: The timestamp for the start of the given epoch
    private func epochToTimestamp(epoch: UInt32) -> Date {
        // GP spec: 10 minutes per epoch (600 seconds)
        let epochDuration: TimeInterval = 600
        let epochStartTime = TimeInterval(epoch) * epochDuration

        // Assume genesis at Unix epoch (can be made configurable if needed)
        return Date(timeIntervalSince1970: epochStartTime)
    }

    // MARK: - Storage Monitoring

    /// Get storage usage statistics
    ///
    /// - Returns: Storage usage information
    public func getStorageUsage() async throws -> StorageUsage {
        let auditEntries = try await dataStore.listAuditEntries(before: Date())
        let d3lEntries = try await dataStore.listD3LEntries(before: Date())

        let auditBundleBytes = auditEntries.reduce(into: 0) { $0 += $1.bundleSize }
        let auditShardBytes = auditEntries.count * 1023 * 684 // 1023 shards per entry

        let d3lShardBytes = d3lEntries.reduce(into: 0) { $0 += Int($1.segmentCount) * 4104 }

        let totalBytes = auditBundleBytes + auditShardBytes + d3lShardBytes
        let entryCount = auditEntries.count + d3lEntries.count

        return StorageUsage(
            totalBytes: totalBytes,
            auditStoreBytes: auditBundleBytes + auditShardBytes,
            d3lStoreBytes: d3lShardBytes,
            entryCount: entryCount,
            auditEntryCount: auditEntries.count,
            d3lEntryCount: d3lEntries.count
        )
    }

    /// Incremental cleanup for large datasets
    ///
    /// Processes data in batches to avoid blocking, saving progress checkpoints.
    ///
    /// - Parameters:
    ///   - batchSize: Maximum number of entries to process per call
    ///   - retentionEpochs: Number of epochs to retain
    /// - Returns: Cleanup progress and statistics
    public func incrementalCleanup(
        batchSize: Int = 100,
        retentionEpochs: UInt32 = 6
    ) async throws -> IncrementalCleanupProgress {
        let epochDuration: TimeInterval = 600 // 10 minutes per epoch
        let cutoffDate = Date().addingTimeInterval(-TimeInterval(retentionEpochs) * epochDuration)

        let entries = try await dataStore.listAuditEntries(before: cutoffDate)

        let totalCount = entries.count
        let batch = Array(entries.prefix(batchSize))

        var deletedCount = 0
        var bytesReclaimed = 0

        for entry in batch {
            try await filesystemStore.deleteAuditBundle(erasureRoot: entry.erasureRoot)
            try await dataStore.deleteAuditEntry(erasureRoot: entry.erasureRoot)
            try await dataStore.deleteShards(erasureRoot: entry.erasureRoot)

            deletedCount += 1
            bytesReclaimed += entry.bundleSize
        }

        return IncrementalCleanupProgress(
            totalEntries: totalCount,
            processedEntries: deletedCount,
            remainingEntries: max(0, totalCount - deletedCount),
            bytesReclaimed: bytesReclaimed,
            isComplete: totalCount <= batchSize
        )
    }

    /// Aggressive cleanup when under storage pressure
    ///
    /// Deletes young data if necessary to free up space.
    /// Uses priority queue to delete oldest and largest entries first.
    ///
    /// - Parameter targetBytes: Target bytes to free (will attempt to free at least this much)
    /// - Returns: Number of bytes actually reclaimed
    public func aggressiveCleanup(targetBytes: Int) async throws -> Int {
        // Use a local actor to protect the shared counter
        actor Counter {
            private var value: Int = 0

            func add(_ amount: Int) {
                value += amount
            }

            func get() -> Int {
                value
            }
        }

        let counter = Counter()

        // Use iterative cleanup to avoid loading all entries into memory at once
        // Process audit entries first (they're older and smaller)
        _ = try await dataStore.cleanupAuditEntriesIteratively(
            before: Date(),
            batchSize: 50 // Smaller batch size to limit memory usage
        ) { batch in
            // Sort batch by timestamp (oldest first) within this batch only
            let sortedBatch = batch.sorted { $0.timestamp < $1.timestamp }

            for entry in sortedBatch {
                // Check if we've met the target
                let current = await counter.get()
                guard current < targetBytes else {
                    return
                }

                do {
                    let size = entry.bundleSize + 1023 * 684 // 1023 shards per entry

                    try await filesystemStore.deleteAuditBundle(erasureRoot: entry.erasureRoot)
                    try await dataStore.deleteAuditEntry(erasureRoot: entry.erasureRoot)
                    try await dataStore.deleteShards(erasureRoot: entry.erasureRoot)

                    // Update counter
                    await counter.add(size)

                    let updated = await counter.get()
                    logger.trace(
                        """
                        Aggressive cleanup: deleted audit entry \(entry.erasureRoot), \
                        freed \(size) bytes (total: \(updated)/\(targetBytes))
                        """
                    )
                } catch {
                    logger.warning("Failed to delete audit entry \(entry.erasureRoot): \(error)")
                }
            }
        }

        // If we haven't met the target yet, process D³L entries
        let currentTotal = await counter.get()
        guard currentTotal < targetBytes else {
            logger.warning("Aggressive cleanup: reclaimed \(currentTotal) bytes (target: \(targetBytes))")
            return currentTotal
        }

        _ = try await dataStore.cleanupD3LEntriesIteratively(
            before: Date(),
            batchSize: 50 // Smaller batch size to limit memory usage
        ) { batch in
            // Sort batch by timestamp (oldest first) within this batch only
            let sortedBatch = batch.sorted { $0.timestamp < $1.timestamp }

            for entry in sortedBatch {
                // Check if we've met the target
                let current = await counter.get()
                guard current < targetBytes else {
                    return
                }

                do {
                    let size = Int(entry.segmentCount) * 4104

                    try await filesystemStore.deleteD3LShards(erasureRoot: entry.erasureRoot)
                    try await dataStore.deleteD3LEntry(erasureRoot: entry.erasureRoot)
                    try await dataStore.deleteShards(erasureRoot: entry.erasureRoot)

                    // Update counter
                    await counter.add(size)

                    let updated = await counter.get()
                    logger.trace(
                        """
                        Aggressive cleanup: deleted D³L entry \(entry.erasureRoot), \
                        freed \(size) bytes (total: \(updated)/\(targetBytes))
                        """
                    )
                } catch {
                    logger.warning("Failed to delete D³L entry \(entry.erasureRoot): \(error)")
                }
            }
        }

        let finalTotal = await counter.get()
        logger.warning("Aggressive cleanup: reclaimed \(finalTotal) bytes (target: \(targetBytes))")

        return finalTotal
    }

    /// Get cleanup metrics
    /// - Returns: Current cleanup metrics
    public func getCleanupMetrics() -> CleanupMetrics {
        cleanupMetrics
    }

    /// Reset cleanup metrics
    public func resetCleanupMetrics() {
        cleanupMetrics = CleanupMetrics()
    }

    // MARK: - Storage Monitoring

    /// Configuration for storage monitoring
    public struct StorageMonitoringConfig: Sendable {
        /// Monitoring interval in seconds (default: 60 seconds)
        public var monitoringInterval: TimeInterval

        /// Maximum storage bytes before triggering cleanup
        public var maxStorageBytes: Int

        /// Storage pressure threshold for aggressive cleanup (0.0-1.0)
        public var aggressiveCleanupThreshold: Double

        /// Whether monitoring is enabled
        public var isEnabled: Bool

        public init(
            monitoringInterval: TimeInterval = 60.0,
            maxStorageBytes: Int = 100 * 1024 * 1024 * 1024, // 100 GB default
            aggressiveCleanupThreshold: Double = 0.85, // 85%
            isEnabled: Bool = true
        ) {
            self.monitoringInterval = monitoringInterval
            self.maxStorageBytes = maxStorageBytes
            self.aggressiveCleanupThreshold = aggressiveCleanupThreshold
            self.isEnabled = isEnabled
        }
    }

    /// Storage monitoring state
    private var monitoringConfig = StorageMonitoringConfig()
    private var monitoringTask: Task<Void, Never>?

    /// Configure storage monitoring
    /// - Parameter config: Monitoring configuration
    public func configureStorageMonitoring(_ config: StorageMonitoringConfig) {
        monitoringConfig = config
        logger.info(
            """
            Storage monitoring configured: interval=\(config.monitoringInterval)s, \
            maxBytes=\(config.maxStorageBytes), \
            threshold=\(Int(config.aggressiveCleanupThreshold * 100))%
            """
        )
    }

    /// Start storage monitoring background task
    ///
    /// Periodically checks storage usage and performs cleanup when needed.
    /// Call this method during service initialization.
    public func startStorageMonitoring() {
        guard monitoringConfig.isEnabled else {
            logger.info("Storage monitoring is disabled")
            return
        }

        // Stop existing task if running
        stopStorageMonitoring()

        // Start new monitoring task
        monitoringTask = Task {
            await runStorageMonitoringLoop()
        }

        logger.info("Started storage monitoring (interval: \(monitoringConfig.monitoringInterval)s)")
    }

    /// Stop storage monitoring background task
    public func stopStorageMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
        logger.info("Stopped storage monitoring")
    }

    /// Storage monitoring loop
    private func runStorageMonitoringLoop() async {
        var consecutiveWarnings = 0
        let maxWarnings = 5 // After 5 warnings, perform aggressive cleanup

        while !Task.isCancelled {
            do {
                let usage = try await getStorageUsage()
                let pressure = StoragePressure.from(usage: usage, maxBytes: monitoringConfig.maxStorageBytes)

                switch pressure {
                case .normal:
                    // Reset warning counter when pressure is normal
                    if consecutiveWarnings > 0 {
                        let maxStorageMB = monitoringConfig.maxStorageBytes / 1024 / 1024
                        logger.info(
                            "Storage pressure returned to normal: \(usage.totalMB) MB / \(maxStorageMB) MB"
                        )
                        consecutiveWarnings = 0
                    }

                case .warning:
                    consecutiveWarnings += 1
                    let maxStorageMB = monitoringConfig.maxStorageBytes / 1024 / 1024
                    let usagePercentage = Int(
                        Double(usage.totalBytes) / Double(monitoringConfig.maxStorageBytes) * 100
                    )
                    logger.warning(
                        "Storage pressure warning: \(usage.totalMB) MB / \(maxStorageMB) MB (\(usagePercentage)% used)"
                    )

                case .critical:
                    consecutiveWarnings += 1
                    let maxStorageMB = monitoringConfig.maxStorageBytes / 1024 / 1024
                    let usagePercentage = Int(
                        Double(usage.totalBytes) / Double(monitoringConfig.maxStorageBytes) * 100
                    )
                    logger.error(
                        "⚠️ CRITICAL storage pressure: \(usage.totalMB) MB / \(maxStorageMB) MB (\(usagePercentage)% used)"
                    )

                    // Perform aggressive cleanup if we haven't recently
                    if consecutiveWarnings >= maxWarnings {
                        logger.error("Initiating aggressive cleanup due to critical storage pressure")

                        let targetBytes = Int(
                            Double(monitoringConfig.maxStorageBytes) * (1.0 - monitoringConfig.aggressiveCleanupThreshold)
                        )
                        let reclaimed = try await aggressiveCleanup(targetBytes: targetBytes)

                        logger.info("Aggressive cleanup reclaimed \(reclaimed) bytes")

                        // Reset counter after cleanup attempt
                        consecutiveWarnings = 0
                    }

                case .emergency:
                    consecutiveWarnings += 1
                    let maxStorageMB = monitoringConfig.maxStorageBytes / 1024 / 1024
                    let usagePercentage = Int(
                        Double(usage.totalBytes) / Double(monitoringConfig.maxStorageBytes) * 100
                    )
                    logger.critical(
                        """
                        🚨 EMERGENCY storage pressure: \(usage.totalMB) MB / \(maxStorageMB) MB \
                        (\(usagePercentage)% used) - System may become unstable!
                        """
                    )

                    // Immediate aggressive cleanup
                    let targetBytes = usage.totalBytes / 2 // Try to free 50%
                    let reclaimed = try await aggressiveCleanup(targetBytes: targetBytes)

                    logger.critical("Emergency cleanup reclaimed \(reclaimed) bytes")
                }

            } catch {
                logger.error("Storage monitoring error: \(error)")
            }

            // Wait for next check (or until cancelled)
            try? await Task.sleep(nanoseconds: UInt64(monitoringConfig.monitoringInterval * 1_000_000_000))
        }

        logger.info("Storage monitoring loop ended")
    }

    /// Get current storage pressure level
    /// - Returns: Current storage pressure
    public func getCurrentStoragePressure() async throws -> StoragePressure {
        let usage = try await getStorageUsage()
        return StoragePressure.from(usage: usage, maxBytes: monitoringConfig.maxStorageBytes)
    }

    // MARK: - Cleanup State Persistence

    /// Save cleanup state to RocksDB metadata
    private func saveCleanupState() async throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(cleanupState)

        // Store in RocksDB metadata with a special key
        let stateKey = Data("__cleanup_state__".utf8)
        try await dataStore.setMetadata(key: stateKey, value: data)

        logger.trace("Saved cleanup state: auditEpoch=\(cleanupState.auditCleanupEpoch), d3lEpoch=\(cleanupState.d3lCleanupEpoch)")
    }

    /// Load cleanup state from RocksDB metadata
    private func loadCleanupState() async throws {
        let stateKey = Data("__cleanup_state__".utf8)

        if let data = try await dataStore.getMetadata(key: stateKey) {
            let decoder = JSONDecoder()
            cleanupState = try decoder.decode(CleanupState.self, from: data)

            logger.debug(
                """
                Loaded cleanup state: auditEpoch=\(cleanupState.auditCleanupEpoch), \
                d3lEpoch=\(cleanupState.d3lCleanupEpoch), \
                inProgress=\(cleanupState.isInProgress)
                """
            )
        } else {
            // No saved state found, use defaults
            cleanupState = CleanupState()
            logger.debug("No saved cleanup state found, using defaults")
        }
    }

    /// Resume incomplete cleanup if state indicates one was in progress
    public func resumeIncompleteCleanupIfNeeded() async throws {
        try await loadCleanupState()

        guard cleanupState.isInProgress else {
            logger.debug("No incomplete cleanup to resume")
            return
        }

        logger.info("Resuming incomplete cleanup from epoch \(cleanupState.auditCleanupEpoch)")

        // Resume audit cleanup
        if cleanupState.auditCleanupEpoch > 0 {
            let (deleted, bytes) = try await cleanupAuditEntriesBeforeEpoch(
                cutoffEpoch: cleanupState.auditCleanupEpoch
            )

            logger.info("Resumed audit cleanup: deleted \(deleted) entries, \(bytes) bytes")
        }

        // Resume D³L cleanup
        if cleanupState.d3lCleanupEpoch > 0 {
            let (deleted, segments) = try await cleanupD3LEntriesBeforeEpoch(
                cutoffEpoch: cleanupState.d3lCleanupEpoch
            )

            logger.info("Resumed D³L cleanup: deleted \(deleted) entries, \(segments) segments")
        }

        // Mark cleanup as complete
        cleanupState.isInProgress = false
        try await saveCleanupState()

        logger.info("Successfully resumed incomplete cleanup")
    }

    // MARK: - Local Shard Retrieval & Caching

    /// Check if a shard exists
    /// - Parameters:
    ///   - erasureRoot: Erasure root identifying the data
    ///   - shardIndex: Index of the shard to check
    /// - Returns: True if the shard exists
    public func hasShard(erasureRoot: Data32, shardIndex: UInt16) async throws -> Bool {
        // Try RocksDB first (for audit shards)
        if let shard = try await dataStore.getShard(erasureRoot: erasureRoot, shardIndex: shardIndex) {
            return true
        }

        // Check filesystem (for D³L shards)
        let filesystemShard = try await filesystemStore.getD3LShard(erasureRoot: erasureRoot, shardIndex: shardIndex)
        return filesystemShard != nil
    }

    /// Get a single shard by erasure root and index
    /// - Parameters:
    ///   - erasureRoot: Erasure root identifying the data
    ///   - shardIndex: Index of the shard to retrieve
    /// - Returns: Shard data or nil if not found
    public func getShard(erasureRoot: Data32, shardIndex: UInt16) async throws -> Data? {
        // Try RocksDB first (for audit shards)
        if let shard = try await dataStore.getShard(erasureRoot: erasureRoot, shardIndex: shardIndex) {
            return shard
        }

        // Fallback to filesystem (for D³L shards)
        return try await filesystemStore.getD3LShard(erasureRoot: erasureRoot, shardIndex: shardIndex)
    }

    /// Get multiple shards in a single batch operation
    /// - Parameters:
    ///   - erasureRoot: Erasure root identifying the data
    ///   - shardIndices: Indices of shards to retrieve
    /// - Returns: Array of tuples containing shard index and data
    public func getShards(erasureRoot: Data32, shardIndices: [UInt16]) async throws -> [(index: UInt16, data: Data)] {
        // Try RocksDB first (for audit shards)
        let rocksDBShards = try await dataStore.getShards(erasureRoot: erasureRoot, shardIndices: shardIndices)

        // For any missing shards, try filesystem (for D³L shards)
        var result: [(index: UInt16, data: Data)] = []
        let foundIndices = Set(rocksDBShards.map(\.index))

        for shardIndex in shardIndices {
            if let shard = rocksDBShards.first(where: { $0.index == shardIndex }) {
                result.append(shard)
            } else if let shardData = try await filesystemStore.getD3LShard(erasureRoot: erasureRoot, shardIndex: shardIndex) {
                result.append((index: shardIndex, data: shardData))
            }
        }

        return result
    }

    /// Get audit entry metadata
    /// - Parameter erasureRoot: Erasure root identifying the data
    /// - Returns: Audit entry or nil if not found
    public func getAuditEntry(erasureRoot: Data32) async throws -> AuditEntry? {
        try await dataStore.getAuditEntry(erasureRoot: erasureRoot)
    }

    /// Get D³L entry by erasure root
    /// - Parameter erasureRoot: Erasure root identifying the data
    /// - Returns: D³L entry or nil if not found
    public func getD3LEntry(erasureRoot: Data32) async throws -> D3LEntry? {
        try await dataStore.getD3LEntry(erasureRoot: erasureRoot)
    }

    /// Get D³L entry by segments root
    /// - Parameter segmentsRoot: Segments root identifying the data
    /// - Returns: D³L entry or nil if not found
    public func getD3LEntry(segmentsRoot: Data32) async throws -> D3LEntry? {
        // First get the erasure root from segments root
        guard let erasureRoot = try await dataStore.getErasureRoot(forSegmentRoot: segmentsRoot) else {
            return nil
        }
        // Then get the D³L entry
        return try await dataStore.getD3LEntry(erasureRoot: erasureRoot)
    }

    /// Get a single segment by erasure root and index
    /// - Parameters:
    ///   - erasureRoot: Erasure root identifying the data
    ///   - segmentIndex: Index of the segment to retrieve
    /// - Returns: Segment data or nil if not found
    public func getSegment(erasureRoot: Data32, segmentIndex: UInt16) async throws -> Data? {
        let segments = try await getSegments(erasureRoot: erasureRoot, indices: [Int(segmentIndex)])
        return segments.first.map(\.data)
    }

    /// Get count of locally available shards for an erasure root
    /// - Parameter erasureRoot: Erasure root identifying the data
    /// - Returns: Number of locally available shards
    public func getLocalShardCount(erasureRoot: Data32) async throws -> Int {
        try await dataStore.getShardCount(erasureRoot: erasureRoot)
    }

    /// Get indices of locally available shards
    /// - Parameter erasureRoot: Erasure root identifying the data
    /// - Returns: Array of available shard indices
    public func getLocalShardIndices(erasureRoot: Data32) async throws -> [UInt16] {
        // Try RocksDB first (for audit shards)
        let rocksDBIndices = try await dataStore.getAvailableShardIndices(erasureRoot: erasureRoot)

        // Also check filesystem (for D³L shards)
        let filesystemIndices = try await filesystemStore.getAvailableShardIndices(erasureRoot: erasureRoot)

        // Merge and deduplicate
        return Set(rocksDBIndices + filesystemIndices).sorted()
    }

    /// Get local shards with caching
    /// - Parameters:
    ///   - erasureRoot: Erasure root identifying the data
    ///   - indices: Shard indices to retrieve
    /// - Returns: Array of shard data tuples
    public func getLocalShards(erasureRoot: Data32, indices: [UInt16]) async throws -> [(index: UInt16, data: Data)] {
        var shards: [(index: UInt16, data: Data)] = []

        for index in indices {
            if let shardData = try await dataStore.getShard(erasureRoot: erasureRoot, shardIndex: index) {
                shards.append((index: index, data: shardData))
            }
        }

        return shards
    }

    /// Get segments with caching support
    /// - Parameters:
    ///   - erasureRoot: Erasure root identifying the data
    ///   - indices: Segment indices to retrieve
    /// - Returns: Array of segments
    public func getSegmentsWithCache(erasureRoot: Data32, indices: [Int]) async throws -> [Data4104] {
        guard let d3lEntry = try await dataStore.getD3LEntry(erasureRoot: erasureRoot) else {
            throw ErasureCodingStoreError.segmentNotFound
        }

        let segmentCount = Int(d3lEntry.segmentCount)
        var segments: [Data4104] = []

        for index in indices {
            guard index < segmentCount else {
                continue
            }

            // Check cache first
            if let cachedSegment = segmentCache.get(segment: Data4104(), erasureRoot: erasureRoot, index: index) {
                segments.append(cachedSegment)
                continue
            }

            // Cache miss - retrieve from storage
            let retrievedSegments = try await getSegments(erasureRoot: erasureRoot, indices: [index])
            if let segment = retrievedSegments.first {
                // Store in cache
                segmentCache.set(segment: segment, erasureRoot: erasureRoot, index: index)
                segments.append(segment)
            }
        }

        return segments
    }

    /// Get segments with network fallback
    /// - Parameters:
    ///   - erasureRoot: Erasure root identifying the data
    ///   - indices: Segment indices to retrieve
    ///   - validators: Optional validator addresses for network fallback
    ///   - coreIndex: Core index for shard assignment (default: 0)
    ///   - totalValidators: Total number of validators (default: 1023)
    /// - Returns: Array of segments
    public func getSegmentsWithNetworkFallback(
        erasureRoot: Data32,
        indices: [Int],
        validators: [UInt16: NetAddr]? = nil,
        coreIndex: UInt16 = 0,
        totalValidators: UInt16 = 1023
    ) async throws -> [Data4104] {
        // Try cache first
        var segments: [Data4104] = []
        var missingIndices: [Int] = []

        for index in indices {
            if let cachedSegment = segmentCache.get(segment: Data4104(), erasureRoot: erasureRoot, index: index) {
                segments.append(cachedSegment)
            } else {
                missingIndices.append(index)
            }
        }

        guard !missingIndices.isEmpty else {
            return segments
        }

        // Try local storage
        do {
            let localSegments = try await getSegmentsWithCache(erasureRoot: erasureRoot, indices: missingIndices)
            segments.append(contentsOf: localSegments)
            return segments
        } catch {
            logger.warning("Failed to retrieve segments from local storage: \(error)")
        }

        // Try network fallback if enabled
        if fetchStrategy != .localOnly,
           let client = networkClient,
           let validatorAddrs = validators,
           !validatorAddrs.isEmpty
        {
            logger.info("Attempting network fallback for segments")

            // Get missing shards for reconstruction
            let missingShards = try await getMissingShardIndices(erasureRoot: erasureRoot)

            // Fetch missing shards
            let fetchedShards = try await client.fetchFromValidatorsConcurrently(
                erasureRoot: erasureRoot,
                shardIndices: Array(missingShards.prefix(cEcOriginalCount)),
                validators: validatorAddrs,
                coreIndex: coreIndex,
                totalValidators: totalValidators,
                requiredShards: max(0, cEcOriginalCount - getLocalShardCount(erasureRoot: erasureRoot))
            )

            // Store fetched shards
            // TODO: For D³L segments, should store to filesystemStore instead of dataStore
            // for consistency with storeExportedSegments. Need to determine if this is
            // a D³L segment vs audit shard. See GP spec for retention requirements.
            for (shardIndex, shardData) in fetchedShards {
                try await dataStore.storeShard(
                    shardData: shardData,
                    erasureRoot: erasureRoot,
                    shardIndex: shardIndex
                )
            }

            // Now get segments from reconstructed data
            let reconstructedSegments = try await getSegmentsWithCache(erasureRoot: erasureRoot, indices: missingIndices)
            segments.append(contentsOf: reconstructedSegments)

            return segments
        }

        throw ErasureCodingStoreError.segmentNotFound
    }

    /// Clear segment cache for a specific erasure root
    /// - Parameter erasureRoot: Erasure root to invalidate
    public func clearCache(erasureRoot: Data32) {
        segmentCache.invalidate(erasureRoot: erasureRoot)
    }

    /// Clear entire segment cache
    public func clearAllCache() {
        segmentCache.clear()
    }

    /// Get cache statistics
    /// - Returns: Cache statistics including hit rate
    public func getCacheStatistics() -> (hits: Int, misses: Int, evictions: Int, size: Int, hitRate: Double) {
        segmentCache.getStatistics()
    }

    // MARK: - Reconstruction from Local Shards

    /// Check if we can reconstruct data from local shards
    /// - Parameter erasureRoot: Erasure root identifying the data
    /// - Returns: True if at least 342 shards are available
    public func canReconstructLocally(erasureRoot: Data32) async throws -> Bool {
        let shardCount = try await getLocalShardCount(erasureRoot: erasureRoot)
        return shardCount >= cEcOriginalCount
    }

    /// Get reconstruction potential
    /// - Parameter erasureRoot: Erasure root identifying the data
    /// - Returns: Percentage of required shards available (capped at 100%)
    public func getReconstructionPotential(erasureRoot: Data32) async throws -> Double {
        let shardCount = try await getLocalShardCount(erasureRoot: erasureRoot)
        let percentage = Double(shardCount) / Double(cEcOriginalCount) * 100.0
        return min(percentage, 100.0)
    }

    /// Get missing shard indices
    /// - Parameter erasureRoot: Erasure root identifying the data
    /// - Returns: Array of missing shard indices
    public func getMissingShardIndices(erasureRoot: Data32) async throws -> [UInt16] {
        let availableIndices = try await getLocalShardIndices(erasureRoot: erasureRoot)
        let availableSet = Set(availableIndices)
        var missing: [UInt16] = []

        for i in 0 ..< 1023 where !availableSet.contains(UInt16(i)) {
            missing.append(UInt16(i))
        }

        return missing
    }

    /// Get reconstruction plan
    /// - Parameter erasureRoot: Erasure root identifying the data
    /// - Returns: Reconstruction plan with status and recommendations
    public func getReconstructionPlan(erasureRoot: Data32) async throws -> ReconstructionPlan {
        let localShards = try await getLocalShardCount(erasureRoot: erasureRoot)
        let missingShards = 1023 - localShards
        let canReconstruct = localShards >= cEcOriginalCount

        return ReconstructionPlan(
            erasureRoot: erasureRoot,
            localShards: localShards,
            missingShards: missingShards,
            canReconstructLocally: canReconstruct,
            reconstructionPercentage: Double(localShards) / Double(cEcOriginalCount) * 100.0
        )
    }

    /// Reconstruct data from local shards if possible
    /// - Parameters:
    ///   - erasureRoot: Erasure root identifying the data
    ///   - originalLength: Expected original data length
    /// - Returns: Reconstructed data
    public func reconstructFromLocalShards(erasureRoot: Data32, originalLength: Int) async throws -> Data {
        guard try await canReconstructLocally(erasureRoot: erasureRoot) else {
            throw try await ErasureCodingStoreError.insufficientShards(
                available: getLocalShardCount(erasureRoot: erasureRoot),
                required: cEcOriginalCount
            )
        }

        let availableIndices = try await getLocalShardIndices(erasureRoot: erasureRoot)
        let shards = try await getLocalShards(erasureRoot: erasureRoot, indices: Array(availableIndices.prefix(cEcOriginalCount)))

        return try await erasureCoding.reconstruct(shards: shards, originalLength: originalLength)
    }

    // MARK: - Batch Operations

    /// Batch get segments for multiple erasure roots
    /// - Parameter requests: Array of segment requests
    /// - Returns: Dictionary mapping erasure root to segments
    public func batchGetSegments(requests: [BatchSegmentRequest]) async throws -> [Data32: [Data4104]] {
        var results: [Data32: [Data4104]] = [:]

        for request in requests {
            do {
                let segments = try await getSegmentsWithCache(
                    erasureRoot: request.erasureRoot,
                    indices: request.indices
                )
                results[request.erasureRoot] = segments
            } catch {
                logger.warning("Failed to retrieve segments for erasureRoot=\(request.erasureRoot.toHexString()): \(error)")
            }
        }

        return results
    }

    /// Batch reconstruction for multiple erasure roots with network fallback
    /// - Parameters:
    ///   - erasureRoots: Erasure roots to reconstruct
    ///   - originalLengths: Mapping of erasure root to original length
    ///   - validators: Optional validator addresses for network fallback
    ///   - coreIndex: Core index for shard assignment (default: 0)
    ///   - totalValidators: Total number of validators (default: 1023)
    /// - Returns: Dictionary mapping erasure root to reconstructed data
    public func batchReconstruct(
        erasureRoots: [Data32],
        originalLengths: [Data32: Int],
        validators: [UInt16: NetAddr]? = nil,
        coreIndex: UInt16 = 0,
        totalValidators: UInt16 = 1023
    ) async throws -> [Data32: Data] {
        // Capture state for TaskGroup closures
        let dataStore = dataStore
        let networkClient = networkClient
        let fetchStrategy = fetchStrategy

        // Limit concurrency
        let maxConcurrentTasks = 10

        // Parallelize reconstruction across erasure roots
        return try await withThrowingTaskGroup(of: (Data32, Data).self) { group in
            var results: [Data32: Data] = [:]
            var activeTasks = 0
            var iterator = erasureRoots.makeIterator()

            // Helper to add next task
            func addNextTask() {
                guard let erasureRoot = iterator.next() else { return }

                activeTasks += 1
                group.addTask {
                    // Check local availability first
                    let canReconstructLocally = try await self.canReconstructLocally(erasureRoot: erasureRoot)

                    if canReconstructLocally {
                        // Try local reconstruction first
                        do {
                            let data = try await self.reconstructFromLocalShards(
                                erasureRoot: erasureRoot,
                                originalLength: originalLengths[erasureRoot] ?? 0
                            )
                            return (erasureRoot, data)
                        } catch {
                            logger.warning("Local reconstruction failed for erasureRoot=\(erasureRoot.toHexString()): \(error)")
                        }
                    }

                    // Try network fallback if enabled and validators available
                    if fetchStrategy != .localOnly,
                       let client = networkClient,
                       let validatorAddrs = validators,
                       !validatorAddrs.isEmpty
                    {
                        do {
                            logger.info("Attempting network fallback for erasureRoot=\(erasureRoot.toHexString())")

                            let missingShards = try await self.getMissingShardIndices(erasureRoot: erasureRoot)

                            // Fetch missing shards from network
                            let fetchedShards = try await client.fetchFromValidatorsConcurrently(
                                erasureRoot: erasureRoot,
                                shardIndices: missingShards,
                                validators: validatorAddrs,
                                coreIndex: coreIndex,
                                totalValidators: totalValidators,
                                requiredShards: max(0, cEcOriginalCount - (self.getLocalShardCount(erasureRoot: erasureRoot)))
                            )

                            // Store fetched shards locally
                            // TODO: For D³L segments, should store to filesystemStore instead of dataStore
                            for (shardIndex, shardData) in fetchedShards {
                                try await dataStore.storeShard(
                                    shardData: shardData,
                                    erasureRoot: erasureRoot,
                                    shardIndex: shardIndex
                                )
                            }

                            // Now reconstruct with combined local + fetched shards
                            let data = try await self.reconstructFromLocalShards(
                                erasureRoot: erasureRoot,
                                originalLength: originalLengths[erasureRoot] ?? 0
                            )

                            logger.info("Successfully reconstructed erasureRoot=\(erasureRoot.toHexString()) with network fallback")
                            return (erasureRoot, data)
                        } catch {
                            logger.error("Network fallback failed for erasureRoot=\(erasureRoot.toHexString()): \(error)")
                            throw error
                        }
                    } else {
                        // No network fallback available, throw error
                        let localShardCount = try await self.getLocalShardCount(erasureRoot: erasureRoot)
                        throw ErasureCodingStoreError.insufficientShards(available: localShardCount, required: cEcOriginalCount)
                    }
                }
            }

            // Start initial batch
            for _ in 0 ..< maxConcurrentTasks {
                addNextTask()
            }

            // Process results and schedule new tasks
            while activeTasks > 0 {
                if let (erasureRoot, data) = try await group.next() {
                    results[erasureRoot] = data
                    activeTasks -= 1
                    addNextTask()
                } else {
                    // Should not happen if activeTasks > 0, but break to avoid infinite loop
                    break
                }
            }

            return results
        }
    }

    /// Batch reconstruction from local shards only
    private func batchReconstructFromLocal(
        erasureRoots: [Data32],
        originalLengths: [Data32: Int]
    ) async throws -> [Data32: Data] {
        // Parallelize local reconstruction
        try await withThrowingTaskGroup(of: (Data32, Data?).self) { group in
            for erasureRoot in erasureRoots {
                group.addTask {
                    guard let originalLength = originalLengths[erasureRoot] else {
                        logger.warning("Missing original length for erasureRoot=\(erasureRoot.toHexString())")
                        return (erasureRoot, nil)
                    }

                    do {
                        let data = try await self.reconstructFromLocalShards(
                            erasureRoot: erasureRoot,
                            originalLength: originalLength
                        )
                        return (erasureRoot, data)
                    } catch {
                        logger.warning("Failed to reconstruct erasureRoot=\(erasureRoot.toHexString()): \(error)")
                        return (erasureRoot, nil)
                    }
                }
            }

            // Collect all results
            var results: [Data32: Data] = [:]
            for try await (erasureRoot, data) in group {
                if let data {
                    results[erasureRoot] = data
                }
            }
            return results
        }
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
}
