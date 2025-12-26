import Foundation
import Utils

public actor InMemoryDataStoreBackend {
    // segment root => erasure root
    private var erasureRootBySegmentRoot: [Data32: Data32] = [:]

    // work package hash => segment root
    private var segmentRootByWorkPackageHash: [Data32: Data32] = [:]

    // erasure root + index => segment data
    private var chunks: [Data32: [UInt16: Data4104]] = [:]

    // erasure root => timestamp
    private var timestamps: [Data32: Date] = [:]

    // erasure root => Paged-Proofs metadata
    private var pagedProofsMetadata: [Data32: Data] = [:]

    // erasure root => audit entry
    private var auditEntries: [Data32: AuditEntry] = [:]

    // erasure root => D³L entry
    private var d3lEntries: [Data32: D3LEntry] = [:]

    // Generic metadata storage
    private var genericMetadata: [Data: Data] = [:]

    public init() {}
}

extension InMemoryDataStoreBackend: DataStoreProtocol {
    public func getErasureRoot(forSegmentRoot: Data32) async throws -> Data32? {
        erasureRootBySegmentRoot[forSegmentRoot]
    }

    public func set(erasureRoot: Data32, forSegmentRoot: Data32) async throws {
        erasureRootBySegmentRoot[forSegmentRoot] = erasureRoot
    }

    public func delete(erasureRoot: Data32) async throws {
        erasureRootBySegmentRoot.removeValue(forKey: erasureRoot)
    }

    public func getSegmentRoot(forWorkPackageHash: Data32) async throws -> Data32? {
        segmentRootByWorkPackageHash[forWorkPackageHash]
    }

    public func set(segmentRoot: Data32, forWorkPackageHash: Data32) async throws {
        segmentRootByWorkPackageHash[forWorkPackageHash] = segmentRoot
    }

    public func delete(segmentRoot: Data32) async throws {
        segmentRootByWorkPackageHash.removeValue(forKey: segmentRoot)
    }

    public func get(erasureRoot: Data32, index: UInt16) async throws -> Data4104? {
        chunks[erasureRoot]?[index]
    }

    public func set(data: Data4104, erasureRoot: Data32, index: UInt16) async throws {
        chunks[erasureRoot, default: [:]][index] = data
    }

    public func setTimestamp(erasureRoot: Data32, timestamp: Date) async throws {
        timestamps[erasureRoot] = timestamp
    }

    public func getTimestamp(erasureRoot: Data32) async throws -> Date? {
        timestamps[erasureRoot]
    }

    public func setPagedProofsMetadata(erasureRoot: Data32, metadata: Data) async throws {
        pagedProofsMetadata[erasureRoot] = metadata
    }

    public func getPagedProofsMetadata(erasureRoot: Data32) async throws -> Data? {
        pagedProofsMetadata[erasureRoot]
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

    public func listAuditEntries(before cutoff: Date) async throws -> [AuditEntry] {
        auditEntries.values.filter { $0.timestamp < cutoff }
    }

    public func deleteAuditEntry(erasureRoot: Data32) async throws {
        auditEntries.removeValue(forKey: erasureRoot)
    }

    public func cleanupAuditEntriesIteratively(
        before cutoff: Date,
        batchSize: Int,
        processor: ([AuditEntry]) async throws -> Void
    ) async throws -> Int {
        let entries = auditEntries.values.filter { $0.timestamp < cutoff }
        var totalProcessed = 0

        for batch in entries.chunked(into: batchSize) {
            try await processor(batch)
            totalProcessed += batch.count
        }

        return totalProcessed
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

    public func listD3LEntries(before cutoff: Date) async throws -> [D3LEntry] {
        d3lEntries.values.filter { $0.timestamp < cutoff }
    }

    public func deleteD3LEntry(erasureRoot: Data32) async throws {
        d3lEntries.removeValue(forKey: erasureRoot)
    }

    public func cleanupD3LEntriesIteratively(
        before cutoff: Date,
        batchSize: Int,
        processor: ([D3LEntry]) async throws -> Void
    ) async throws -> Int {
        let entries = d3lEntries.values.filter { $0.timestamp < cutoff }
        var totalProcessed = 0

        for batch in entries.chunked(into: batchSize) {
            try await processor(batch)
            totalProcessed += batch.count
        }

        return totalProcessed
    }

    // MARK: - Shard Operations

    public func storeShard(shardData: Data, erasureRoot: Data32, shardIndex: UInt16) async throws {
        guard let segment = Data4104(shardData) else {
            return
        }
        chunks[erasureRoot, default: [:]][shardIndex] = segment
    }

    public func getShard(erasureRoot: Data32, shardIndex: UInt16) async throws -> Data? {
        chunks[erasureRoot]?[shardIndex]?.data
    }

    public func getShards(erasureRoot: Data32, shardIndices: [UInt16]) async throws -> [(index: UInt16, data: Data)] {
        var result: [(index: UInt16, data: Data)] = []
        for index in shardIndices {
            if let shard = try await getShard(erasureRoot: erasureRoot, shardIndex: index) {
                result.append((index, shard))
            }
        }
        return result
    }

    public func storeShards(shards: [(index: UInt16, data: Data)], erasureRoot: Data32) async throws {
        for shard in shards {
            try await storeShard(shardData: shard.data, erasureRoot: erasureRoot, shardIndex: shard.index)
        }
    }

    public func deleteShards(erasureRoot: Data32) async throws {
        chunks.removeValue(forKey: erasureRoot)
    }

    public func getShardCount(erasureRoot: Data32) async throws -> Int {
        chunks[erasureRoot]?.count ?? 0
    }

    public func getAvailableShardIndices(erasureRoot: Data32) async throws -> [UInt16] {
        chunks[erasureRoot]?.keys.sorted() ?? []
    }

    // MARK: - Generic Metadata Storage

    public func setMetadata(key: Data, value: Data) async throws {
        genericMetadata[key] = value
    }

    public func getMetadata(key: Data) async throws -> Data? {
        genericMetadata[key]
    }
}

extension InMemoryDataStoreBackend: DataStoreNetworkProtocol {
    public func fetchRemoteChunk(erasureRoot _: Data32, shardIndex _: UInt16, segmentIndices _: [UInt16]) async throws -> Data12? {
        nil
    }
}

// MARK: - Array Helper

extension Array {
    fileprivate func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
