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
