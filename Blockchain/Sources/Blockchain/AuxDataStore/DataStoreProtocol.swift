import Foundation
import Utils

public protocol DataStoreProtocol: Sendable {
    // segment root => erasure root
    func getErasureRoot(forSegmentRoot: Data32) async throws -> Data32?
    func set(erasureRoot: Data32, forSegmentRoot: Data32) async throws
    func delete(erasureRoot: Data32) async throws

    // work package hash => segment root
    func getSegmentRoot(forWorkPackageHash: Data32) async throws -> Data32?
    func set(segmentRoot: Data32, forWorkPackageHash: Data32) async throws
    func delete(segmentRoot: Data32) async throws

    // erasure root + index => segment data
    func get(erasureRoot: Data32, index: UInt16) async throws -> Data4104?
    func set(data: Data4104, erasureRoot: Data32, index: UInt16) async throws

    // New methods for timestamp and Paged-Proofs metadata
    func setTimestamp(erasureRoot: Data32, timestamp: Date) async throws
    func getTimestamp(erasureRoot: Data32) async throws -> Date?

    func setPagedProofsMetadata(erasureRoot: Data32, metadata: Data) async throws
    func getPagedProofsMetadata(erasureRoot: Data32) async throws -> Data?

    // MARK: - Audit Entry Operations

    func setAuditEntry(workPackageHash: Data32, erasureRoot: Data32, bundleSize: Int, timestamp: Date) async throws
    func getAuditEntry(erasureRoot: Data32) async throws -> AuditEntry?
    func listAuditEntries(before: Date) async throws -> [AuditEntry]
    func deleteAuditEntry(erasureRoot: Data32) async throws
    func cleanupAuditEntriesIteratively(before: Date, batchSize: Int, processor: ([AuditEntry]) async throws -> Void) async throws -> Int

    // MARK: - D³L Entry Operations

    func setD3LEntry(segmentsRoot: Data32, erasureRoot: Data32, segmentCount: UInt32, timestamp: Date) async throws
    func getD3LEntry(erasureRoot: Data32) async throws -> D3LEntry?
    func listD3LEntries(before: Date) async throws -> [D3LEntry]
    func deleteD3LEntry(erasureRoot: Data32) async throws
    func cleanupD3LEntriesIteratively(before: Date, batchSize: Int, processor: ([D3LEntry]) async throws -> Void) async throws -> Int

    // MARK: - Shard Operations

    func storeShard(shardData: Data, erasureRoot: Data32, shardIndex: UInt16) async throws
    func getShard(erasureRoot: Data32, shardIndex: UInt16) async throws -> Data?
    func getShards(erasureRoot: Data32, shardIndices: [UInt16]) async throws -> [(index: UInt16, data: Data)]
    func storeShards(shards: [(index: UInt16, data: Data)], erasureRoot: Data32) async throws
    func deleteShards(erasureRoot: Data32) async throws
    func getShardCount(erasureRoot: Data32) async throws -> Int
    func getAvailableShardIndices(erasureRoot: Data32) async throws -> [UInt16]

    // MARK: - Generic Metadata Storage

    func setMetadata(key: Data, value: Data) async throws
    func getMetadata(key: Data) async throws -> Data?
}

// MARK: - Supporting Types

public struct AuditEntry: Sendable, Codable {
    public var workPackageHash: Data32
    public var erasureRoot: Data32
    public var bundleSize: Int
    public var timestamp: Date

    public init(workPackageHash: Data32, erasureRoot: Data32, bundleSize: Int, timestamp: Date) {
        self.workPackageHash = workPackageHash
        self.erasureRoot = erasureRoot
        self.bundleSize = bundleSize
        self.timestamp = timestamp
    }
}

public struct D3LEntry: Sendable, Codable {
    public var segmentsRoot: Data32
    public var erasureRoot: Data32
    public var segmentCount: UInt32
    public var timestamp: Date

    public init(segmentsRoot: Data32, erasureRoot: Data32, segmentCount: UInt32, timestamp: Date) {
        self.segmentsRoot = segmentsRoot
        self.erasureRoot = erasureRoot
        self.segmentCount = segmentCount
        self.timestamp = timestamp
    }
}

public protocol DataStoreNetworkProtocol: Sendable {
    // Use CE139/CE140 to fetch remote chunk
    func fetchRemoteChunk(erasureRoot: Data32, shardIndex: UInt16, segmentIndices: [UInt16]) async throws -> Data12?
}
