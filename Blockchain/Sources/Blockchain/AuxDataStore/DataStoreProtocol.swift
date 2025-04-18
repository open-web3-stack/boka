import Foundation
import Utils

public protocol DataStoreProtocol: Sendable {
    // segment root => erasure root
    func getEasureRoot(forSegmentRoot: Data32) async throws -> Data32?
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
}

public protocol DataStoreNetworkProtocol: Sendable {
    // Use CE139/CE140 to fetch remote chunk
    func fetchRemoteChunk(erasureRoot: Data32, shardIndex: UInt16, segmentIndices: [UInt16]) async throws -> Data12?
}
