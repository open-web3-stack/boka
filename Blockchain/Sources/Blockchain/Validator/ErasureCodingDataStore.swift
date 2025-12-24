import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "ErasureCodingDataStore")

/// Enhanced data store that automatically handles erasure coding for availability system
///
/// This service sits on top of RocksDBDataStore and FilesystemDataStore, providing
/// automatic erasure coding/decoding for segments and bundles.
public actor ErasureCodingDataStore {
    private let rocksdbStore: RocksDBDataStore
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

    // Expose rocksdbStore for testing purposes
    public var rocksdbStoreForTesting: RocksDBDataStore {
        rocksdbStore
    }

    public init(
        rocksdbStore: RocksDBDataStore,
        filesystemStore: FilesystemDataStore,
        config: ProtocolConfigRef,
        networkClient: AvailabilityNetworkClient? = nil
    ) {
        self.rocksdbStore = rocksdbStore
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
            throw DataAvailabilityError.bundleTooLarge(size: bundle.count, maxSize: maxBundleSize)
        }

        // Erasure-code the bundle
        let shards = try erasureCoding.encodeBlob(bundle)

        // Calculate erasure root
        let erasureRoot = try erasureCoding.calculateErasureRoot(
            segmentsRoot: segmentsRoot,
            shards: shards
        )

        // Store bundle in filesystem (for quick retrieval)
        try await filesystemStore.storeAuditBundle(erasureRoot: erasureRoot, data: bundle)

        // Store shards in RocksDB (for distributed access)
        let shardTuples = shards.enumerated().map { index, data in
            (index: UInt16(index), data: data)
        }
        try await rocksdbStore.storeShards(shards: shardTuples, erasureRoot: erasureRoot)

        // Store metadata
        try await rocksdbStore.setTimestamp(erasureRoot: erasureRoot, timestamp: Date())
        try await rocksdbStore.setAuditEntry(
            workPackageHash: workPackageHash,
            erasureRoot: erasureRoot,
            bundleSize: bundle.count,
            timestamp: Date()
        )
        try await rocksdbStore.set(erasureRoot: erasureRoot, forSegmentRoot: segmentsRoot)

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
        let indices = try await rocksdbStore.getAvailableShardIndices(erasureRoot: erasureRoot)
        guard indices.count >= 342 else {
            logger.warning("Insufficient shards for reconstruction: \(indices.count)/342")
            return nil
        }

        let shards = try await rocksdbStore.getShards(erasureRoot: erasureRoot, shardIndices: Array(indices.prefix(342)))

        // Determine original size from audit metadata
        guard let auditEntry = try await rocksdbStore.getAuditEntry(erasureRoot: erasureRoot) else {
            return nil
        }

        // Reconstruct
        let reconstructed = try erasureCoding.reconstruct(
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
            throw DataAvailabilityError.noSegmentsToStore
        }

        // Validate segment count (GP spec: max 3,072)
        guard segments.count <= 3072 else {
            throw DataAvailabilityError.tooManySegments(count: segments.count, max: 3072)
        }

        logger.debug("Storing \(segments.count) exported segments: workPackageHash=\(workPackageHash.toHexString())")

        // Calculate segments root Merkle tree
        let calculatedSegmentsRoot = Merklization.binaryMerklize(segments.map(\.data))
        #expect(calculatedSegmentsRoot == segmentsRoot)

        // Generate Paged-Proofs metadata
        let pagedProofsMetadata = try generatePagedProofsMetadata(segments: segments)

        // Encode all segments together
        let shards = try erasureCoding.encodeSegments(segments)

        // Calculate erasure root
        let erasureRoot = try erasureCoding.calculateErasureRoot(
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
        try await rocksdbStore.setTimestamp(erasureRoot: erasureRoot, timestamp: Date())
        try await rocksdbStore.setPagedProofsMetadata(erasureRoot: erasureRoot, metadata: pagedProofsMetadata)
        try await rocksdbStore.setD3LEntry(
            segmentsRoot: segmentsRoot,
            erasureRoot: erasureRoot,
            segmentCount: UInt32(segments.count),
            timestamp: Date()
        )
        try await rocksdbStore.set(segmentRoot: segmentsRoot, forWorkPackageHash: workPackageHash)
        try await rocksdbStore.set(erasureRoot: erasureRoot, forSegmentRoot: segmentsRoot)

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
        let availableShardIndices = try await rocksdbStore.getAvailableShardIndices(erasureRoot: erasureRoot)

        // Check if we can reconstruct
        guard availableShardIndices.count >= 342 else {
            throw DataAvailabilityError.insufficientShards(
                available: availableShardIndices.count,
                required: 342
            )
        }

        // Get shards for reconstruction
        let shardTuples = try await rocksdbStore.getShards(
            erasureRoot: erasureRoot,
            shardIndices: Array(availableShardIndices.prefix(342))
        )

        // Get segment count from metadata
        guard let d3lEntry = try await rocksdbStore.getD3LEntry(erasureRoot: erasureRoot) else {
            throw DataAvailabilityError.metadataNotFound(erasureRoot: erasureRoot)
        }

        let segmentCount = Int(d3lEntry.segmentCount)
        let originalLength = segmentCount * 4104

        // Reconstruct segments
        let reconstructedData = try erasureCoding.reconstruct(
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
        guard let d3lEntry = try await rocksdbStore.getD3LEntry(erasureRoot: erasureRoot) else {
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
        guard let d3lEntry = try await rocksdbStore.getD3LEntry(erasureRoot: erasureRoot) else {
            throw DataAvailabilityError.metadataNotFound(erasureRoot: erasureRoot)
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
        try await rocksdbStore.getPagedProofsMetadata(erasureRoot: erasureRoot)
    }

    /// Get the number of pages for an erasure root
    ///
    /// - Parameter erasureRoot: Erasure root identifying the segments
    /// - Returns: Number of pages, or nil if not found
    public func getPageCount(erasureRoot: Data32) async throws -> Int? {
        guard let d3lEntry = try await rocksdbStore.getD3LEntry(erasureRoot: erasureRoot) else {
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
        let encoded = JamEncoder.encode(pageCount, segmentsRoot, pages)

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
                case let .left(hash):
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
    /// - Parameter retentionEpochs: Number of epochs to retain (default: 6)
    public func cleanupAuditEntries(retentionEpochs: UInt32 = 6) async throws -> (entriesDeleted: Int, bytesReclaimed: Int) {
        let epochDuration: TimeInterval = 600 // 10 minutes per epoch (GP spec)
        let cutoffDate = Date().addingTimeInterval(-TimeInterval(retentionEpochs) * epochDuration)

        let entries = try await rocksdbStore.listAuditEntries(before: cutoffDate)

        var deletedCount = 0
        var bytesReclaimed = 0

        for entry in entries {
            // Delete from filesystem
            try await filesystemStore.deleteAuditBundle(erasureRoot: entry.erasureRoot)

            // Delete from RocksDB
            try await rocksdbStore.deleteAuditEntry(erasureRoot: entry.erasureRoot)
            try await rocksdbStore.deleteShards(erasureRoot: entry.erasureRoot)

            deletedCount += 1
            bytesReclaimed += entry.bundleSize
        }

        logger.info("Cleanup: deleted \(deletedCount) audit entries, reclaimed \(bytesReclaimed) bytes")

        return (deletedCount, bytesReclaimed)
    }

    /// Cleanup expired D³L entries (older than retention period)
    ///
    /// - Parameter retentionEpochs: Number of epochs to retain (default: 672)
    public func cleanupD3LEntries(retentionEpochs: UInt32 = 672) async throws -> (entriesDeleted: Int, segmentsDeleted: Int) {
        let epochDuration: TimeInterval = 600 // 10 minutes per epoch
        let cutoffDate = Date().addingTimeInterval(-TimeInterval(retentionEpochs) * epochDuration)

        let entries = try await rocksdbStore.listD3LEntries(before: cutoffDate)

        var deletedEntries = 0
        var deletedSegments = 0

        for entry in entries {
            // Delete from filesystem
            try await filesystemStore.deleteD3LShards(erasureRoot: entry.erasureRoot)

            // Delete from RocksDB
            try await rocksdbStore.deleteD3LEntry(erasureRoot: entry.erasureRoot)
            try await rocksdbStore.deleteShards(erasureRoot: entry.erasureRoot)

            deletedEntries += 1
            deletedSegments += Int(entry.segmentCount)
        }

        logger.info("Cleanup: deleted \(deletedEntries) D³L entries, \(deletedSegments) segments")

        return (deletedEntries, deletedSegments)
    }

    /// Cleanup expired audit entries (older than cutoff epoch)
    ///
    /// - Parameter cutoffEpoch: Cleanup entries from epochs before this value
    /// - Returns: Tuple of (entries deleted, bytes reclaimed)
    public func cleanupAuditEntriesBeforeEpoch(cutoffEpoch: UInt32) async throws -> (entriesDeleted: Int, bytesReclaimed: Int) {
        let startTime = Date()
        let cutoffDate = epochToTimestamp(epoch: cutoffEpoch)

        let entries = try await rocksdbStore.listAuditEntries(before: cutoffDate)

        var deletedCount = 0
        var bytesReclaimed = 0

        for entry in entries {
            // Delete from filesystem
            try await filesystemStore.deleteAuditBundle(erasureRoot: entry.erasureRoot)

            // Delete from RocksDB
            try await rocksdbStore.deleteAuditEntry(erasureRoot: entry.erasureRoot)
            try await rocksdbStore.deleteShards(erasureRoot: entry.erasureRoot)

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

        let entries = try await rocksdbStore.listD3LEntries(before: cutoffDate)

        var deletedEntries = 0
        var deletedSegments = 0

        for entry in entries {
            // Delete from filesystem
            try await filesystemStore.deleteD3LShards(erasureRoot: entry.erasureRoot)

            // Delete from RocksDB
            try await rocksdbStore.deleteD3LEntry(erasureRoot: entry.erasureRoot)
            try await rocksdbStore.deleteShards(erasureRoot: entry.erasureRoot)

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
        let auditEntries = try await rocksdbStore.listAuditEntries(before: Date())
        let d3lEntries = try await rocksdbStore.listD3LEntries(before: Date())

        let auditBundleBytes = auditEntries.reduce(0) { $0 + $1.bundleSize }
        let auditShardBytes = auditEntries.reduce(0) { $0 + Int($1.shardCount) * 684 } // Approximate shard size

        let d3lShardBytes = d3lEntries.reduce(0) { $0 + Int($1.segmentCount) * 4104 }

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

        let entries = try await rocksdbStore.listAuditEntries(before: cutoffDate)

        let totalCount = entries.count
        let batch = Array(entries.prefix(batchSize))

        var deletedCount = 0
        var bytesReclaimed = 0

        for entry in batch {
            try await filesystemStore.deleteAuditBundle(erasureRoot: entry.erasureRoot)
            try await rocksdbStore.deleteAuditEntry(erasureRoot: entry.erasureRoot)
            try await rocksdbStore.deleteShards(erasureRoot: entry.erasureRoot)

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
    ///
    /// - Parameter targetBytes: Target bytes to free (will attempt to free at least this much)
    /// - Returns: Number of bytes actually reclaimed
    public func aggressiveCleanup(targetBytes: Int) async throws -> Int {
        var bytesReclaimed = 0
        var retentionEpochs: UInt32 = 6

        // First try normal cleanup
        while bytesReclaimed < targetBytes, retentionEpochs > 0 {
            let (deleted, bytes) = try await cleanupAuditEntries(retentionEpochs: retentionEpochs)
            bytesReclaimed += bytes

            if deleted == 0 {
                // No more entries at this retention level
                retentionEpochs -= 1
            } else {
                break
            }
        }

        // If still need more space, clean up D³L entries aggressively
        if bytesReclaimed < targetBytes {
            retentionEpochs = 672
            while bytesReclaimed < targetBytes, retentionEpochs > 100 {
                let (entriesDeleted, segmentsDeleted) = try await cleanupD3LEntries(retentionEpochs: retentionEpochs)
                bytesReclaimed += segmentsDeleted * 4104

                if entriesDeleted == 0 {
                    retentionEpochs = UInt32(Double(retentionEpochs) * 0.8) // Reduce by 20%
                } else {
                    break
                }
            }
        }

        logger.warning("Aggressive cleanup: reclaimed \(bytesReclaimed) bytes (target: \(targetBytes))")

        return bytesReclaimed
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

    // MARK: - Local Shard Retrieval & Caching

    /// Get count of locally available shards for an erasure root
    /// - Parameter erasureRoot: Erasure root identifying the data
    /// - Returns: Number of locally available shards
    public func getLocalShardCount(erasureRoot: Data32) async throws -> Int {
        try await rocksdbStore.getShardCount(erasureRoot: erasureRoot)
    }

    /// Get indices of locally available shards
    /// - Parameter erasureRoot: Erasure root identifying the data
    /// - Returns: Array of available shard indices
    public func getLocalShardIndices(erasureRoot: Data32) async throws -> [UInt16] {
        try await rocksdbStore.getAvailableShardIndices(erasureRoot: erasureRoot)
    }

    /// Get local shards with caching
    /// - Parameters:
    ///   - erasureRoot: Erasure root identifying the data
    ///   - indices: Shard indices to retrieve
    /// - Returns: Array of shard data tuples
    public func getLocalShards(erasureRoot: Data32, indices: [UInt16]) async throws -> [(index: UInt16, data: Data)] {
        var shards: [(index: UInt16, data: Data)] = []

        for index in indices {
            if let shardData = try await rocksdbStore.getShard(erasureRoot: erasureRoot, shardIndex: index) {
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
        guard let d3lEntry = try await rocksdbStore.getD3LEntry(erasureRoot: erasureRoot) else {
            throw DataAvailabilityError.segmentNotFound
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
                shardIndices: Array(missingShards.prefix(342)),
                validators: validatorAddrs,
                coreIndex: coreIndex,
                totalValidators: totalValidators,
                requiredShards: max(0, 342 - getLocalShardCount(erasureRoot: erasureRoot))
            )

            // Store fetched shards
            for (shardIndex, shardData) in fetchedShards {
                try await rocksdbStore.storeShard(
                    shard: shardData,
                    index: shardIndex,
                    erasureRoot: erasureRoot
                )
            }

            // Now get segments from reconstructed data
            let reconstructedSegments = try await getSegmentsWithCache(erasureRoot: erasureRoot, indices: missingIndices)
            segments.append(contentsOf: reconstructedSegments)

            return segments
        }

        throw DataAvailabilityError.segmentNotFound
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
        return shardCount >= 342
    }

    /// Get reconstruction potential
    /// - Parameter erasureRoot: Erasure root identifying the data
    /// - Returns: Percentage of required shards available (capped at 100%)
    public func getReconstructionPotential(erasureRoot: Data32) async throws -> Double {
        let shardCount = try await getLocalShardCount(erasureRoot: erasureRoot)
        let percentage = Double(shardCount) / 342.0 * 100.0
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
        let canReconstruct = localShards >= 342

        return ReconstructionPlan(
            erasureRoot: erasureRoot,
            localShards: localShards,
            missingShards: missingShards,
            canReconstructLocally: canReconstruct,
            reconstructionPercentage: Double(localShards) / 342.0 * 100.0
        )
    }

    /// Reconstruct data from local shards if possible
    /// - Parameters:
    ///   - erasureRoot: Erasure root identifying the data
    ///   - originalLength: Expected original data length
    /// - Returns: Reconstructed data
    public func reconstructFromLocalShards(erasureRoot: Data32, originalLength: Int) async throws -> Data {
        guard try await canReconstructLocally(erasureRoot: erasureRoot) else {
            throw try await DataAvailabilityError.insufficientShards(
                available: getLocalShardCount(erasureRoot: erasureRoot),
                required: 342
            )
        }

        let availableIndices = try await getLocalShardIndices(erasureRoot: erasureRoot)
        let shards = try await getLocalShards(erasureRoot: erasureRoot, indices: Array(availableIndices.prefix(342)))

        return try erasureCoding.reconstruct(shards: shards, originalLength: originalLength)
    }

    // MARK: - Batch Operations

    /// Batch get segments for multiple erasure roots
    /// - Parameter requests: Array of segment requests
    /// - Returns: Dictionary mapping erasure root to segments
    public func batchGetSegments(requests: [SegmentRequest]) async throws -> [Data32: [Data4104]] {
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
        var results: [Data32: Data] = [:]

        for erasureRoot in erasureRoots {
            // Check local availability first
            let canReconstructLocally = try await canReconstructLocally(erasureRoot: erasureRoot)

            if canReconstructLocally {
                // Try local reconstruction first
                do {
                    let data = try await reconstructFromLocalShards(
                        erasureRoot: erasureRoot,
                        originalLength: originalLengths[erasureRoot] ?? 0
                    )
                    results[erasureRoot] = data
                    continue
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

                    let missingShards = try await getMissingShardIndices(erasureRoot: erasureRoot)

                    // Fetch missing shards from network
                    let fetchedShards = try await client.fetchFromValidatorsConcurrently(
                        erasureRoot: erasureRoot,
                        shardIndices: missingShards,
                        validators: validatorAddrs,
                        coreIndex: coreIndex,
                        totalValidators: totalValidators,
                        requiredShards: max(0, 342 - getLocalShardCount(erasureRoot: erasureRoot))
                    )

                    // Store fetched shards locally
                    for (shardIndex, shardData) in fetchedShards {
                        try await rocksdbStore.storeShard(
                            shard: shardData,
                            index: shardIndex,
                            erasureRoot: erasureRoot
                        )
                    }

                    // Now reconstruct with combined local + fetched shards
                    let data = try await reconstructFromLocalShards(
                        erasureRoot: erasureRoot,
                        originalLength: originalLengths[erasureRoot] ?? 0
                    )
                    results[erasureRoot] = data

                    logger.info("Successfully reconstructed erasureRoot=\(erasureRoot.toHexString()) with network fallback")
                } catch {
                    logger.error("Network fallback failed for erasureRoot=\(erasureRoot.toHexString()): \(error)")
                    throw error
                }
            } else {
                // No network fallback available, throw error
                let localShardCount = try await getLocalShardCount(erasureRoot: erasureRoot)
                throw DataAvailabilityError.insufficientShards(available: localShardCount, required: 342)
            }
        }

        return results
    }

    /// Batch reconstruction from local shards only
    private func batchReconstructFromLocal(
        erasureRoots: [Data32],
        originalLengths: [Data32: Int]
    ) async throws -> [Data32: Data] {
        var results: [Data32: Data] = [:]

        for erasureRoot in erasureRoots {
            guard let originalLength = originalLengths[erasureRoot] else {
                logger.warning("Missing original length for erasureRoot=\(erasureRoot.toHexString())")
                continue
            }

            do {
                let data = try await reconstructFromLocalShards(
                    erasureRoot: erasureRoot,
                    originalLength: originalLength
                )
                results[erasureRoot] = data
            } catch {
                logger.warning("Failed to reconstruct erasureRoot=\(erasureRoot.toHexString()): \(error)")
            }
        }

        return results
    }
}

// MARK: - Supporting Types

/// Segment request for batch operations
public struct SegmentRequest: Sendable {
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

// MARK: - Errors

public enum DataAvailabilityError: Error {
    case bundleTooLarge(size: Int, maxSize: Int)
    case noSegmentsToStore
    case tooManySegments(count: Int, max: Int)
    case insufficientShards(available: Int, required: Int)
    case metadataNotFound(erasureRoot: Data32)
    case reconstructionFailed(underlying: Error)
    case segmentNotFound
}
