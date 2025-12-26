@testable import Blockchain
import Foundation
import TracingUtils
import Utils

/// In-memory implementation of DataStoreProtocol for testing
///
/// This is a simple actor-based store that keeps all data in memory.
/// It's fast, easy to use in tests, and requires no external dependencies.
public actor InMemoryDataStore: DataStoreProtocol {
    // MARK: - Storage

    private var erasureRoots: [Data32: Data32] = [:]
    private var segmentRoots: [Data32: Data32] = [:]
    private var segments: [Data32: [UInt16: Data4104]] = [:]
    private var timestamps: [Data32: Date] = [:]
    private var pagedProofs: [Data32: Data] = [:]
    private var auditEntries: [Data32: AuditEntry] = [:]
    private var d3lEntries: [Data32: D3LEntry] = [:]
    private var shards: [Data32: [UInt16: Data]] = [:]
    private var metadata: [Data: Data] = [:]

    // MARK: - Erasure Root Operations

    public func getErasureRoot(forSegmentRoot: Data32) async throws -> Data32? {
        erasureRoots[forSegmentRoot]
    }

    public func set(erasureRoot: Data32, forSegmentRoot: Data32) async throws {
        erasureRoots[forSegmentRoot] = erasureRoot
    }

    public func delete(erasureRoot: Data32) async throws {
        // Remove all associated data
        erasureRoots.values.removeAll { $0 == erasureRoot }
        segments.removeValue(forKey: erasureRoot)
        timestamps.removeValue(forKey: erasureRoot)
        pagedProofs.removeValue(forKey: erasureRoot)
        auditEntries.removeValue(forKey: erasureRoot)
        d3lEntries.removeValue(forKey: erasureRoot)
        shards.removeValue(forKey: erasureRoot)
    }

    // MARK: - Segment Root Operations

    public func getSegmentRoot(forWorkPackageHash: Data32) async throws -> Data32? {
        segmentRoots[forWorkPackageHash]
    }

    public func set(segmentRoot: Data32, forWorkPackageHash: Data32) async throws {
        segmentRoots[forWorkPackageHash] = segmentRoot
    }

    public func delete(segmentRoot: Data32) async throws {
        segmentRoots.values.removeAll { $0 == segmentRoot }
    }

    // MARK: - Segment Operations

    public func get(erasureRoot: Data32, index: UInt16) async throws -> Data4104? {
        segments[erasureRoot]?[index]
    }

    public func set(data: Data4104, erasureRoot: Data32, index: UInt16) async throws {
        if segments[erasureRoot] == nil {
            segments[erasureRoot] = [:]
        }
        segments[erasureRoot]?[index] = data
    }

    // MARK: - Timestamp Operations

    public func setTimestamp(erasureRoot: Data32, timestamp: Date) async throws {
        timestamps[erasureRoot] = timestamp
    }

    public func getTimestamp(erasureRoot: Data32) async throws -> Date? {
        timestamps[erasureRoot]
    }

    // MARK: - Paged Proofs Operations

    public func setPagedProofsMetadata(erasureRoot: Data32, metadata: Data) async throws {
        pagedProofs[erasureRoot] = metadata
    }

    public func getPagedProofsMetadata(erasureRoot: Data32) async throws -> Data? {
        pagedProofs[erasureRoot]
    }

    // MARK: - Audit Entry Operations

    public func setAuditEntry(workPackageHash: Data32, erasureRoot: Data32, bundleSize: Int, timestamp: Date) async throws {
        auditEntries[erasureRoot] = AuditEntry(
            workPackageHash: workPackageHash,
            erasureRoot: erasureRoot,
            bundleSize: bundleSize,
            timestamp: timestamp
        )
    }

    public func getAuditEntry(erasureRoot: Data32) async throws -> AuditEntry? {
        auditEntries[erasureRoot]
    }

    public func listAuditEntries(before: Date) async throws -> [AuditEntry] {
        auditEntries.values.filter { $0.timestamp < before }
            .sorted { $0.timestamp < $1.timestamp }
    }

    public func deleteAuditEntry(erasureRoot: Data32) async throws {
        auditEntries.removeValue(forKey: erasureRoot)
    }

    public func cleanupAuditEntriesIteratively(
        before: Date,
        batchSize: Int,
        processor: @Sendable ([AuditEntry]) async throws -> Void
    ) async throws -> Int {
        var count = 0
        let entries = auditEntries.values.filter { $0.timestamp < before }

        for chunk in entries.chunked(into: batchSize) {
            try await processor(chunk)
            count += chunk.count
        }

        for entry in entries {
            auditEntries.removeValue(forKey: entry.erasureRoot)
        }

        return count
    }

    // MARK: - D³L Entry Operations

    public func setD3LEntry(segmentsRoot: Data32, erasureRoot: Data32, segmentCount: UInt32, timestamp: Date) async throws {
        d3lEntries[erasureRoot] = D3LEntry(
            segmentsRoot: segmentsRoot,
            erasureRoot: erasureRoot,
            segmentCount: segmentCount,
            timestamp: timestamp
        )
    }

    public func getD3LEntry(erasureRoot: Data32) async throws -> D3LEntry? {
        d3lEntries[erasureRoot]
    }

    public func listD3LEntries(before: Date) async throws -> [D3LEntry] {
        d3lEntries.values.filter { $0.timestamp < before }
            .sorted { $0.timestamp < $1.timestamp }
    }

    public func deleteD3LEntry(erasureRoot: Data32) async throws {
        d3lEntries.removeValue(forKey: erasureRoot)
    }

    public func cleanupD3LEntriesIteratively(
        before: Date,
        batchSize: Int,
        processor: @Sendable ([D3LEntry]) async throws -> Void
    ) async throws -> Int {
        var count = 0
        let entries = d3lEntries.values.filter { $0.timestamp < before }

        for chunk in entries.chunked(into: batchSize) {
            try await processor(chunk)
            count += chunk.count
        }

        for entry in entries {
            d3lEntries.removeValue(forKey: entry.erasureRoot)
        }

        return count
    }

    // MARK: - Shard Operations

    public func storeShard(shardData: Data, erasureRoot: Data32, shardIndex: UInt16) async throws {
        if shards[erasureRoot] == nil {
            shards[erasureRoot] = [:]
        }
        shards[erasureRoot]?[shardIndex] = shardData
    }

    public func getShard(erasureRoot: Data32, shardIndex: UInt16) async throws -> Data? {
        shards[erasureRoot]?[shardIndex]
    }

    public func getShards(erasureRoot: Data32, shardIndices: [UInt16]) async throws -> [(index: UInt16, data: Data)] {
        shardIndices.compactMap { index in
            guard let data = shards[erasureRoot]?[index] else {
                return nil
            }
            return (index, data)
        }
    }

    public func storeShards(shards: [(index: UInt16, data: Data)], erasureRoot: Data32) async throws {
        for shard in shards {
            try await storeShard(shardData: shard.data, erasureRoot: erasureRoot, shardIndex: shard.index)
        }
    }

    public func deleteShards(erasureRoot: Data32) async throws {
        shards.removeValue(forKey: erasureRoot)
    }

    public func getShardCount(erasureRoot: Data32) async throws -> Int {
        shards[erasureRoot]?.count ?? 0
    }

    public func getAvailableShardIndices(erasureRoot: Data32) async throws -> [UInt16] {
        shards[erasureRoot]?.keys.sorted() ?? []
    }

    // MARK: - Metadata Operations

    public func setMetadata(key: Data, value: Data) async throws {
        metadata[key] = value
    }

    public func getMetadata(key: Data) async throws -> Data? {
        metadata[key]
    }

    // MARK: - Test Helpers

    /// Clear all stored data
    public func clear() {
        erasureRoots.removeAll()
        segmentRoots.removeAll()
        segments.removeAll()
        timestamps.removeAll()
        pagedProofs.removeAll()
        auditEntries.removeAll()
        d3lEntries.removeAll()
        shards.removeAll()
        metadata.removeAll()
    }

    /// Get total count of stored items across all categories
    public var totalCount: Int {
        erasureRoots.count + segmentRoots.count + segments.count +
            timestamps.count + auditEntries.count + d3lEntries.count +
            shards.count + metadata.count
    }
}

// MARK: - Helper Extensions

extension Array {
    /// Splits array into chunks of specified size
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
