import Blockchain
import Codec
import Foundation
import RocksDBSwift
import TracingUtils
import Utils

private let logger = Logger(label: "RocksDBDataStore")

/// Errors that can occur in RocksDB operations
public enum RocksDBError: Error {
    case invalidShardDataSize(actual: Int, expected: Int)
    case writeFailed(underlying: Error)
    case readFailed(underlying: Error)
}

/// RocksDB-backed implementation of DataStoreProtocol for availability system
///
/// Storage Layout:
/// - availabilityMetadata: erasureRoot => (timestamp, pagedProofsHash, shardCount)
/// - availabilitySegments: erasureRoot || index => segmentData
/// - availabilityMappings:
///   - 0x01 || workPackageHash => segmentsRoot
///   - 0x02 || segmentsRoot => erasureRoot
/// - availabilityAudit: erasureRoot => (workPackageHash, bundleSize, timestamp)
/// - availabilityD3L: erasureRoot => (segmentsRoot, segmentCount, timestamp)
public final actor RocksDBDataStore {
    private let db: RocksDB<StoreId>
    private let config: ProtocolConfigRef

    // Column families
    private let metadata: Store<StoreId, JamCoder<Data32, AvailabilityMetadata>>
    private let segments: Store<StoreId, JamCoder<Data, Data>> // Changed from Data4104 to Data for variable-length shards
    private let mappings: Store<StoreId, JamCoder<Data, Data32>>
    private let audit: Store<StoreId, JamCoder<Data32, AuditEntry>>
    private let d3l: Store<StoreId, JamCoder<Data32, D3LEntry>>

    // Key prefixes for mappings
    private static let workPackageHashPrefix = Data([0x01])
    private static let segmentsRootPrefix = Data([0x02]) // Maps segmentsRoot → audit erasure root
    private static let d3lSegmentsRootPrefix = Data([0x03]) // Maps segmentsRoot → D³L erasure root

    init(db: RocksDB<StoreId>, config: ProtocolConfigRef) {
        self.db = db
        self.config = config

        // Initialize column family stores
        metadata = Store<StoreId, JamCoder<Data32, AvailabilityMetadata>>(
            db: db,
            column: .availabilityMetadata,
            coder: JamCoder(config: config)
        )
        segments = Store<StoreId, JamCoder<Data, Data>>(db: db, column: .availabilitySegments, coder: JamCoder(config: config))
        mappings = Store<StoreId, JamCoder<Data, Data32>>(db: db, column: .availabilityMappings, coder: JamCoder(config: config))
        audit = Store<StoreId, JamCoder<Data32, AuditEntry>>(db: db, column: .availabilityAudit, coder: JamCoder(config: config))
        d3l = Store<StoreId, JamCoder<Data32, D3LEntry>>(db: db, column: .availabilityD3L, coder: JamCoder(config: config))
    }
}

// MARK: - DataStoreProtocol Implementation

extension RocksDBDataStore: DataStoreProtocol {
    /// Get erasure root for a given segment root
    public func getErasureRoot(forSegmentRoot segmentRoot: Data32) async throws -> Data32? {
        let key = Self.segmentsRootPrefix + segmentRoot.data
        return try mappings.get(key: key)
    }

    /// Map segment root to erasure root
    public func set(erasureRoot: Data32, forSegmentRoot segmentRoot: Data32) async throws {
        let key = Self.segmentsRootPrefix + segmentRoot.data
        try mappings.put(key: key, value: erasureRoot)
    }

    /// Delete erasure root mapping
    public func delete(erasureRoot _: Data32) async throws {
        // This removes from segment root -> erasure root mapping
        // To fully delete, we'd need to iterate and find the key, but for now
        // we rely on timestamp-based cleanup
    }

    /// Get segment root for work package hash
    public func getSegmentRoot(forWorkPackageHash workPackageHash: Data32) async throws -> Data32? {
        let key = Self.workPackageHashPrefix + workPackageHash.data
        return try mappings.get(key: key)
    }

    /// Map work package hash to segment root
    public func set(segmentRoot: Data32, forWorkPackageHash workPackageHash: Data32) async throws {
        let key = Self.workPackageHashPrefix + workPackageHash.data
        try mappings.put(key: key, value: segmentRoot)
    }

    /// Delete segment root mapping
    public func delete(segmentRoot: Data32) async throws {
        try mappings.delete(key: segmentRoot.data)
    }

    // MARK: - D³L Erasure Root Mapping

    /// Get D³L erasure root for a given segments root
    public func getD3LErasureRoot(forSegmentsRoot segmentsRoot: Data32) async throws -> Data32? {
        let key = Self.d3lSegmentsRootPrefix + segmentsRoot.data
        return try mappings.get(key: key)
    }

    /// Map segments root to D³L erasure root (separate from audit erasure root mapping)
    public func set(d3lErasureRoot: Data32, forSegmentsRoot segmentsRoot: Data32) async throws {
        let key = Self.d3lSegmentsRootPrefix + segmentsRoot.data
        try mappings.put(key: key, value: d3lErasureRoot)
        logger.trace("Mapped segmentsRoot to D³L erasure root: segmentsRoot=\(segmentsRoot.toHexString())")
    }

    /// Get segment data by erasure root and index
    public func get(erasureRoot: Data32, index: UInt16) async throws -> Data? {
        let key = makeSegmentKey(erasureRoot: erasureRoot, index: index)
        return try segments.get(key: key)
    }

    /// Store segment data
    public func set(data: Data, erasureRoot: Data32, index: UInt16) async throws {
        let key = makeSegmentKey(erasureRoot: erasureRoot, index: index)
        try segments.put(key: key, value: data)
        logger.trace("Stored segment: erasureRoot=\(erasureRoot.toHexString()), index=\(index)")
    }

    /// Set timestamp for erasure root
    public func setTimestamp(erasureRoot: Data32, timestamp: Date) async throws {
        var meta = try await getOrCreateMetadata(erasureRoot: erasureRoot)
        meta.timestamp = timestamp
        try metadata.put(key: erasureRoot, value: meta)
    }

    /// Get timestamp for erasure root
    public func getTimestamp(erasureRoot: Data32) async throws -> Date? {
        let meta = try metadata.get(key: erasureRoot)
        return meta?.timestamp
    }

    /// Set Paged-Proofs metadata
    public func setPagedProofsMetadata(erasureRoot: Data32, metadata: Data) async throws {
        var meta = try await getOrCreateMetadata(erasureRoot: erasureRoot)
        meta.pagedProofsHash = metadata.blake2b256hash()
        meta.pagedProofsMetadata = metadata
        try self.metadata.put(key: erasureRoot, value: meta)
        logger.trace("Set Paged-Proofs metadata: erasureRoot=\(erasureRoot.toHexString())")
    }

    /// Get Paged-Proofs metadata
    public func getPagedProofsMetadata(erasureRoot: Data32) async throws -> Data? {
        let meta = try metadata.get(key: erasureRoot)
        return meta?.pagedProofsMetadata
    }
}

// MARK: - Audit & D³L Operations

extension RocksDBDataStore {
    /// Store audit entry (short-term)
    public func setAuditEntry(
        workPackageHash: Data32,
        erasureRoot: Data32,
        segmentsRoot: Data32,
        bundleSize: Int,
        timestamp: Date
    ) async throws {
        let entry = AuditEntry(
            workPackageHash: workPackageHash,
            erasureRoot: erasureRoot,
            segmentsRoot: segmentsRoot,
            bundleSize: bundleSize,
            timestamp: timestamp
        )
        try audit.put(key: erasureRoot, value: entry)
        logger.debug("Stored audit entry: erasureRoot=\(erasureRoot.toHexString()), size=\(bundleSize)")
    }

    /// Get audit entry
    public func getAuditEntry(erasureRoot: Data32) async throws -> AuditEntry? {
        try audit.get(key: erasureRoot)
    }

    /// List audit entries before a given timestamp (for cleanup)
    public func listAuditEntries(before cutoff: Date) async throws -> [AuditEntry] {
        var entries: [AuditEntry] = []

        let iterator = db.createIterator(column: .availabilityAudit, readOptions: ReadOptions())

        iterator.seek(to: Data())

        while let (key, value) = iterator.read(), key.count == 32 {
            let entry = try JamDecoder.decode(AuditEntry.self, from: value)
            if entry.timestamp < cutoff {
                entries.append(entry)
            }
            iterator.next()
        }

        return entries
    }

    /// Delete audit entry
    public func deleteAuditEntry(erasureRoot: Data32) async throws {
        try audit.delete(key: erasureRoot)
        logger.trace("Deleted audit entry: erasureRoot=\(erasureRoot.toHexString())")
    }

    /// Cleanup audit entries iteratively (memory-efficient for large datasets)
    ///
    /// Processes entries in batches using a callback, avoiding loading all entries into memory.
    /// The processor callback can return false to stop iteration early.
    ///
    /// - Parameters:
    ///   - cutoff: Timestamp cutoff (delete entries older than this)
    ///   - batchSize: Maximum number of entries to process per batch
    ///   - processor: Callback to process each batch of entries. Return false to stop iteration.
    /// - Returns: Total number of entries processed
    public func cleanupAuditEntriesIteratively(
        before cutoff: Date,
        batchSize: Int = 100,
        processor: @Sendable ([AuditEntry]) async throws -> Bool
    ) async throws -> Int {
        var totalProcessed = 0
        var batch: [AuditEntry] = []
        batch.reserveCapacity(batchSize)

        let iterator = db.createIterator(column: .availabilityAudit, readOptions: ReadOptions())

        iterator.seek(to: Data())

        while let (key, value) = iterator.read(), key.count == 32 {
            let entry = try JamDecoder.decode(AuditEntry.self, from: value)
            if entry.timestamp < cutoff {
                batch.append(entry)
                totalProcessed += 1

                // Process batch when it reaches the batch size
                if batch.count >= batchSize {
                    let shouldContinue = try await processor(batch)
                    batch.removeAll()

                    // Early termination if processor returns false
                    if !shouldContinue {
                        break
                    }
                }
            }
            iterator.next()
        }

        // Process any remaining entries in the final batch
        if !batch.isEmpty {
            let shouldContinue = try await processor(batch)
            if !shouldContinue {
                return totalProcessed
            }
        }

        return totalProcessed
    }

    /// Store D³L entry (long-term)
    public func setD3LEntry(segmentsRoot: Data32, erasureRoot: Data32, segmentCount: UInt32, timestamp: Date) async throws {
        let entry = D3LEntry(
            segmentsRoot: segmentsRoot,
            erasureRoot: erasureRoot,
            segmentCount: segmentCount,
            timestamp: timestamp
        )
        try d3l.put(key: erasureRoot, value: entry)
        logger.debug("Stored D³L entry: erasureRoot=\(erasureRoot.toHexString()), count=\(segmentCount)")
    }

    /// Get D³L entry
    public func getD3LEntry(erasureRoot: Data32) async throws -> D3LEntry? {
        try d3l.get(key: erasureRoot)
    }

    /// List D³L entries before a given timestamp (for cleanup)
    public func listD3LEntries(before cutoff: Date) async throws -> [D3LEntry] {
        var entries: [D3LEntry] = []

        let iterator = db.createIterator(column: .availabilityD3L, readOptions: ReadOptions())

        iterator.seek(to: Data())

        while let (key, value) = iterator.read(), key.count == 32 {
            let entry = try JamDecoder.decode(D3LEntry.self, from: value)
            if entry.timestamp < cutoff {
                entries.append(entry)
            }
            iterator.next()
        }

        return entries
    }

    /// Delete D³L entry
    public func deleteD3LEntry(erasureRoot: Data32) async throws {
        try d3l.delete(key: erasureRoot)
        logger.trace("Deleted D³L entry: erasureRoot=\(erasureRoot.toHexString())")
    }

    /// Cleanup D³L entries iteratively (memory-efficient for large datasets)
    ///
    /// Processes entries in batches using a callback, avoiding loading all entries into memory.
    /// The processor callback can return false to stop iteration early.
    ///
    /// - Parameters:
    ///   - cutoff: Timestamp cutoff (delete entries older than this)
    ///   - batchSize: Maximum number of entries to process per batch
    ///   - processor: Callback to process each batch of entries. Return false to stop iteration.
    /// - Returns: Total number of entries processed
    public func cleanupD3LEntriesIteratively(
        before cutoff: Date,
        batchSize: Int = 100,
        processor: @Sendable ([D3LEntry]) async throws -> Bool
    ) async throws -> Int {
        var totalProcessed = 0
        var batch: [D3LEntry] = []
        batch.reserveCapacity(batchSize)

        let iterator = db.createIterator(column: .availabilityD3L, readOptions: ReadOptions())

        iterator.seek(to: Data())

        while let (key, value) = iterator.read(), key.count == 32 {
            let entry = try JamDecoder.decode(D3LEntry.self, from: value)
            if entry.timestamp < cutoff {
                batch.append(entry)
                totalProcessed += 1

                // Process batch when it reaches the batch size
                if batch.count >= batchSize {
                    let shouldContinue = try await processor(batch)
                    batch.removeAll()

                    // Early termination if processor returns false
                    if !shouldContinue {
                        break
                    }
                }
            }
            iterator.next()
        }

        // Process any remaining entries in the final batch
        if !batch.isEmpty {
            let shouldContinue = try await processor(batch)
            if !shouldContinue {
                return totalProcessed
            }
        }

        return totalProcessed
    }

    /// Get storage statistics
    public func getStatistics() async throws -> (auditCount: Int, d3lCount: Int, totalSegments: Int) {
        var auditCount = 0
        var d3lCount = 0
        var totalSegments = 0

        // Count audit entries
        let auditIterator = db.createIterator(column: .availabilityAudit, readOptions: ReadOptions())
        auditIterator.seek(to: Data())
        while auditIterator.read() != nil {
            auditCount += 1
            auditIterator.next()
        }

        // Count D³L entries and segments
        let d3lIterator = db.createIterator(column: .availabilityD3L, readOptions: ReadOptions())
        d3lIterator.seek(to: Data())
        while let (_, value) = d3lIterator.read() {
            d3lCount += 1
            let entry = try JamDecoder.decode(D3LEntry.self, from: value)
            totalSegments += Int(entry.segmentCount)
            d3lIterator.next()
        }

        return (auditCount, d3lCount, totalSegments)
    }
}

// MARK: - Shard-Level Operations

extension RocksDBDataStore {
    /// Store a single shard for an erasure root
    /// - Parameters:
    ///   - shardData: Raw shard data (erasure-coded piece)
    ///   - erasureRoot: Erasure root identifying the data
    ///   - shardIndex: Index of the shard (0-1022)
    public func storeShard(shardData: Data, erasureRoot: Data32, shardIndex: UInt16) async throws {
        let key = makeShardKey(erasureRoot: erasureRoot, shardIndex: shardIndex)

        // TODO: Atomicity issue - these two writes should be in a single batch
        // If the process crashes between them, the shard exists but shardCount is incorrect
        // Should use RocksDB's WriteBatch to ensure atomicity:
        // db.batch { |batch| batch.put(key, shardData); batch.put(erasureRoot, meta) }

        // Store variable-length shard data directly (no longer constrained to 4104 bytes)
        // This supports both audit bundle shards (variable-sized) and D³L segment shards (4104 bytes)
        try segments.put(key: key, value: shardData)

        // Update metadata
        var meta = try await getOrCreateMetadata(erasureRoot: erasureRoot)
        meta.shardCount += 1
        try metadata.put(key: erasureRoot, value: meta)

        logger.trace("Stored shard \(shardIndex) (size: \(shardData.count) bytes) for erasureRoot=\(erasureRoot.toHexString())")
    }

    /// Retrieve a single shard by erasure root and index
    /// - Parameters:
    ///   - erasureRoot: Erasure root identifying the data
    ///   - shardIndex: Index of the shard (0-1022)
    /// - Returns: Shard data or nil if not found
    public func getShard(erasureRoot: Data32, shardIndex: UInt16) async throws -> Data? {
        let key = makeShardKey(erasureRoot: erasureRoot, shardIndex: shardIndex)
        return try segments.get(key: key)
    }

    /// Get count of available shards for an erasure root
    /// - Parameter erasureRoot: Erasure root identifying the data
    /// - Returns: Number of shards stored (0-1023)
    public func getShardCount(erasureRoot: Data32) async throws -> Int {
        guard let meta = try metadata.get(key: erasureRoot) else {
            return 0
        }
        return Int(meta.shardCount)
    }

    /// Check if we have enough shards to reconstruct (≥342)
    /// - Parameter erasureRoot: Erasure root identifying the data
    /// - Returns: True if reconstruction is possible
    public func canReconstruct(erasureRoot: Data32) async throws -> Bool {
        let count = try await getShardCount(erasureRoot: erasureRoot)
        return count >= 342
    }

    /// Get all available shard indices for an erasure root
    /// - Parameter erasureRoot: Erasure root identifying the data
    /// - Returns: Array of available shard indices
    public func getAvailableShardIndices(erasureRoot: Data32) async throws -> [UInt16] {
        var indices: [UInt16] = []

        let iterator = db.createIterator(column: .availabilitySegments, readOptions: ReadOptions())

        // Seek to first key with this erasure root prefix
        let prefix = erasureRoot.data
        iterator.seek(to: prefix)

        while let (key, _) = iterator.read() {
            // Check if key starts with erasure root
            guard key.starts(with: prefix) else {
                break
            }

            // Extract shard index from key (erasureRoot || index)
            if key.count == prefix.count + 2 {
                let indexData = key.suffix(from: prefix.count)
                if indexData.count == 2 {
                    // Use loadUnaligned for safety since Data slices are not guaranteed to be aligned
                    let index = indexData.withUnsafeBytes { bytes in
                        bytes.loadUnaligned(as: UInt16.self).bigEndian
                    }
                    indices.append(index)
                }
            }

            iterator.next()
        }

        return indices.sorted()
    }

    /// Batch store multiple shards atomically using batch operations
    /// - Parameters:
    ///   - shards: Array of (index, data) tuples
    ///   - erasureRoot: Erasure root identifying the data
    public func storeShards(shards: [(index: UInt16, data: Data)], erasureRoot: Data32) async throws {
        var operations: [BatchOperation] = []

        // Add all shard writes to the batch
        for shard in shards {
            let key = makeShardKey(erasureRoot: erasureRoot, shardIndex: shard.index)

            // Store variable-length shard data directly (no longer constrained to 4104 bytes)
            try operations.append(segments.putOperation(key: key, value: shard.data))
        }

        // Update metadata
        var meta = try await getOrCreateMetadata(erasureRoot: erasureRoot)
        meta.shardCount += UInt32(shards.count) // Increment, don't overwrite
        try operations.append(metadata.putOperation(key: erasureRoot, value: meta))

        // Write everything atomically
        try db.batch(operations: operations)

        logger.debug("Stored \(shards.count) shards atomically for erasureRoot=\(erasureRoot.toHexString())")
    }

    /// Batch retrieve multiple shards
    /// - Parameters:
    ///   - erasureRoot: Erasure root identifying the data
    ///   - shardIndices: Array of shard indices to retrieve
    /// - Returns: Array of (index, data) tuples for found shards
    public func getShards(erasureRoot: Data32, shardIndices: [UInt16]) async throws -> [(index: UInt16, data: Data)] {
        var result: [(index: UInt16, data: Data)] = []

        for index in shardIndices {
            if let shard = try await getShard(erasureRoot: erasureRoot, shardIndex: index) {
                result.append((index, shard))
            }
        }

        logger.trace("Retrieved \(result.count)/\(shardIndices.count) shards for erasureRoot=\(erasureRoot.toHexString())")

        return result
    }

    /// Delete all shards for an erasure root
    /// - Parameter erasureRoot: Erasure root identifying the data
    public func deleteShards(erasureRoot: Data32) async throws {
        let indices = try await getAvailableShardIndices(erasureRoot: erasureRoot)

        for index in indices {
            let key = makeShardKey(erasureRoot: erasureRoot, shardIndex: index)
            try segments.delete(key: key)
        }

        // Update metadata
        var meta = try await getOrCreateMetadata(erasureRoot: erasureRoot)
        meta.shardCount = 0
        try metadata.put(key: erasureRoot, value: meta)

        logger.debug("Deleted \(indices.count) shards for erasureRoot=\(erasureRoot.toHexString())")
    }
}

// MARK: - Helper Methods

extension RocksDBDataStore {
    /// Create segment storage key from erasure root and index
    private func makeSegmentKey(erasureRoot: Data32, index: UInt16) -> Data {
        erasureRoot.data + Data(withUnsafeBytes(of: index.bigEndian) { Array($0) })
    }

    /// Create shard storage key from erasure root and shard index
    private func makeShardKey(erasureRoot: Data32, shardIndex: UInt16) -> Data {
        erasureRoot.data + Data(withUnsafeBytes(of: shardIndex.bigEndian) { Array($0) })
    }

    /// Get or create metadata for erasure root
    private func getOrCreateMetadata(erasureRoot: Data32) async throws -> AvailabilityMetadata {
        if let existing = try metadata.get(key: erasureRoot) {
            return existing
        }
        return AvailabilityMetadata(
            timestamp: Date(),
            pagedProofsHash: Data32(),
            pagedProofsMetadata: Data(),
            shardCount: 0
        )
    }

    // MARK: - Generic Metadata Storage

    /// Store arbitrary metadata with a custom key
    /// - Parameters:
    ///   - key: Custom key for the metadata
    ///   - value: Metadata value to store
    public func setMetadata(key: Data, value: Data) async throws {
        // Hash the key directly - we don't need a prefix since erasure roots are
        // derived from different data (shard hashes + segments root)
        let keyData32 = key.blake2b256hash()

        let metadataValue = AvailabilityMetadata(
            timestamp: Date(),
            pagedProofsHash: keyData32,
            pagedProofsMetadata: value,
            shardCount: UInt32(value.count)
        )
        try metadata.put(key: keyData32, value: metadataValue)
        logger.trace("Stored metadata: key=\(key.base64EncodedString()), size=\(value.count)")
    }

    /// Retrieve arbitrary metadata by custom key
    /// - Parameter key: Custom key for the metadata
    /// - Returns: Metadata value if found, nil otherwise
    public func getMetadata(key: Data) async throws -> Data? {
        let keyData32 = key.blake2b256hash()

        if let metadataValue = try metadata.get(key: keyData32) {
            return metadataValue.pagedProofsMetadata
        }
        return nil
    }

    /// Delete metadata by custom key
    /// - Parameter key: Custom key for the metadata to delete
    public func deleteMetadata(key: Data) async throws {
        let keyData32 = key.blake2b256hash()
        try metadata.delete(key: keyData32)
        logger.trace("Deleted metadata: key=\(key.base64EncodedString())")
    }
}

// MARK: - Data Structures

/// Metadata for availability entries
private struct AvailabilityMetadata: Codable {
    var timestamp: Date
    var pagedProofsHash: Data32
    var pagedProofsMetadata: Data
    var shardCount: UInt32
}

// MARK: - Put Helper

extension AvailabilityMetadata {
    fileprivate func put(to store: Store<StoreId, JamCoder<Data32, AvailabilityMetadata>>, erasureRoot: Data32) throws {
        try store.put(key: erasureRoot, value: self)
    }
}
