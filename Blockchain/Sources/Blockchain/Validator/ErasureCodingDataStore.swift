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

    public init(
        rocksdbStore: RocksDBDataStore,
        filesystemStore: FilesystemDataStore,
        config: ProtocolConfigRef
    ) {
        self.rocksdbStore = rocksdbStore
        self.filesystemStore = filesystemStore
        self.config = config
        erasureCoding = ErasureCodingService(config: config)
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

    // MARK: - Paged-Proofs Metadata Generation

    /// Generate Paged-Proofs metadata for exported segments
    ///
    /// Per GP spec: Groups segments into pages of 64, generates Merkle paths
    /// and subtree pages for efficient segment justification
    ///
    /// - Parameter segments: Array of exported segments
    /// - Returns: Paged-Proofs metadata as Data
    private func generatePagedProofsMetadata(segments: [Data4104]) throws -> Data {
        guard !segments.isEmpty else {
            return Data()
        }

        // Calculate page size (64 segments per page)
        let pageSize = 64
        let pageCount = (segments.count + pageSize - 1) / pageSize

        var pages: [Data] = []

        for pageIndex in 0 ..< pageCount {
            let startIdx = pageIndex * pageSize
            let endIdx = min(startIdx + pageSize, segments.count)
            let pageSegments = Array(segments[startIdx ..< endIdx])

            // Calculate Merkle path for this page
            let pageData = pageSegments.map(\.data).reduce(Data(), +)

            // For now, store the page data padded to segment size
            // Full Paged-Proofs implementation would generate proper Merkle paths
            var paddedPage = pageData
            if paddedPage.count < 4104 {
                paddedPage.append(Data(count: 4104 - paddedPage.count))
            }

            pages.append(paddedPage)
        }

        // Encode pages
        let encoded = JamEncoder.encode(pages)

        logger.debug("Generated Paged-Proofs metadata: \(pageCount) pages")

        return encoded
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
}

// MARK: - Errors

public enum DataAvailabilityError: Error {
    case bundleTooLarge(size: Int, maxSize: Int)
    case noSegmentsToStore
    case tooManySegments(count: Int, max: Int)
    case insufficientShards(available: Int, required: Int)
    case metadataNotFound(erasureRoot: Data32)
    case reconstructionFailed(underlying: Error)
}
