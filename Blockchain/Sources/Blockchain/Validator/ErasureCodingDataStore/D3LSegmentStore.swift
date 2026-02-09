import Codec
import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "D3LSegmentStore")
private let cEcOriginalCount = 342

/// Service for storing and retrieving D³L segments with erasure coding
///
/// Per GP spec: Stores exported segments with Paged-Proofs metadata
/// - Erasure-codes each segment individually (4,104 bytes → 1,023 shards of 12 bytes)
/// - Stores shards in filesystem under d3l/ directory
/// - Generates and stores Paged-Proofs metadata
/// - Sets timestamp for retention tracking (672 epochs = 28 days)
public actor D3LSegmentStore {
    private let dataStore: any DataStoreProtocol
    private let filesystemStore: FilesystemDataStore
    private let erasureCoding: ErasureCodingService
    private let pagedProofsGenerator: PagedProofsGenerator

    public init(
        dataStore: any DataStoreProtocol,
        filesystemStore: FilesystemDataStore,
        erasureCoding: ErasureCodingService,
        pagedProofsGenerator: PagedProofsGenerator,
    ) {
        self.dataStore = dataStore
        self.filesystemStore = filesystemStore
        self.erasureCoding = erasureCoding
        self.pagedProofsGenerator = pagedProofsGenerator
    }

    /// Store exported segments with automatic erasure coding
    ///
    /// - Parameters:
    ///   - segments: Array of exported segments (4,104 bytes each)
    ///   - workPackageHash: Hash of the work package
    ///   - segmentsRoot: Merkle root of the segments
    /// - Returns: Erasure root for the stored segments
    public func storeSegments(
        segments: [Data4104],
        workPackageHash: Data32,
        segmentsRoot: Data32,
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
                expected: segmentsRoot,
            )
        }

        // Generate Paged-Proofs metadata
        let pagedProofsMetadata = try await pagedProofsGenerator.generateMetadata(segments: segments)

        // Encode all segments together
        let shards = try await erasureCoding.encodeSegments(segments)

        // Calculate erasure root
        let erasureRoot = try await erasureCoding.calculateErasureRoot(
            segmentsRoot: segmentsRoot,
            shards: shards,
        )

        // Store each shard's individual data in parallel using TaskGroup
        // This is much more efficient than sequential await for 1023 shards
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, shard) in shards.enumerated() {
                group.addTask { [weak self] in
                    guard let self else {
                        return
                    }
                    try await filesystemStore.storeD3LShard(
                        erasureRoot: erasureRoot,
                        shardIndex: UInt16(index),
                        data: shard,
                    )
                }
            }

            // Wait for all tasks to complete and rethrow any errors
            try await group.waitForAll()
        }

        // Store metadata
        try await dataStore.setTimestamp(erasureRoot: erasureRoot, timestamp: Date())
        try await dataStore.setPagedProofsMetadata(erasureRoot: erasureRoot, metadata: pagedProofsMetadata)
        try await dataStore.setD3LEntry(
            segmentsRoot: segmentsRoot,
            erasureRoot: erasureRoot,
            segmentCount: UInt32(segments.count),
            timestamp: Date(),
        )
        try await dataStore.set(segmentRoot: segmentsRoot, forWorkPackageHash: workPackageHash)
        // Use separate D³L mapping to avoid collision with audit erasure root mapping
        try await dataStore.set(d3lErasureRoot: erasureRoot, forSegmentsRoot: segmentsRoot)

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
                required: cEcOriginalCount,
            )
        }

        // Get shards for reconstruction
        let shardTuples = try await dataStore.getShards(
            erasureRoot: erasureRoot,
            shardIndices: Array(availableShardIndices.prefix(cEcOriginalCount)),
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
            originalLength: originalLength,
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

    /// Get a single segment by erasure root and index
    /// - Parameters:
    ///   - erasureRoot: Erasure root identifying the segments
    ///   - segmentIndex: Index of the segment to retrieve
    /// - Returns: Segment data or nil if not found
    public func getSegment(erasureRoot: Data32, segmentIndex: UInt16) async throws -> Data? {
        let segments = try await getSegments(erasureRoot: erasureRoot, indices: [Int(segmentIndex)])
        return segments.first.map(\.data)
    }
}
