import Foundation
import Utils

/// Service for retrieving shards and segments with caching support
public actor ShardRetrieval {
    private let dataStore: any DataStoreProtocol
    private let filesystemStore: FilesystemDataStore
    private let segmentCache: SegmentCache

    public init(
        dataStore: any DataStoreProtocol,
        filesystemStore: FilesystemDataStore,
        segmentCache: SegmentCache,
    ) {
        self.dataStore = dataStore
        self.filesystemStore = filesystemStore
        self.segmentCache = segmentCache
    }

    // MARK: - Shard Operations

    /// Check if a shard exists
    /// - Parameters:
    ///   - erasureRoot: Erasure root identifying the data
    ///   - shardIndex: Index of the shard to check
    /// - Returns: True if the shard exists
    public func hasShard(erasureRoot: Data32, shardIndex: UInt16) async throws -> Bool {
        // Try RocksDB first (for audit shards)
        if try await dataStore.getShard(erasureRoot: erasureRoot, shardIndex: shardIndex) != nil {
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

        // Convert to dictionary for O(1) lookups instead of O(N*M) nested loop
        let rocksDBShardsDict = Dictionary(uniqueKeysWithValues: rocksDBShards.map { ($0.index, $0.data) })

        // For any missing shards, try filesystem (for D³L shards)
        var result: [(index: UInt16, data: Data)] = []

        for shardIndex in shardIndices {
            if let shardData = rocksDBShardsDict[shardIndex] {
                result.append((index: shardIndex, data: shardData))
            } else if let shardData = try await filesystemStore.getD3LShard(erasureRoot: erasureRoot, shardIndex: shardIndex) {
                result.append((index: shardIndex, data: shardData))
            }
        }

        return result
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

    // MARK: - Metadata Operations

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
        // First get the erasure root from segments root using the D³L-specific mapping
        guard let erasureRoot = try await dataStore.getD3LErasureRoot(forSegmentsRoot: segmentsRoot) else {
            return nil
        }
        // Then get the D³L entry
        return try await dataStore.getD3LEntry(erasureRoot: erasureRoot)
    }

    /// Get D³L erasure root for a given segments root
    /// - Parameter segmentsRoot: Segments root identifying the data
    /// - Returns: D³L erasure root or nil if not found
    public func getD3LErasureRoot(forSegmentsRoot segmentsRoot: Data32) async throws -> Data32? {
        try await dataStore.getD3LErasureRoot(forSegmentsRoot: segmentsRoot)
    }

    // MARK: - Cache Management

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
}
