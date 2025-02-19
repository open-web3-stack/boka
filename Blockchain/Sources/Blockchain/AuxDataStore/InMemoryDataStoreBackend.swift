import Utils

public actor InMemoryDataStoreBackend {
    // segment root => erasure root
    private var erasureRootBySegmentRoot: [Data32: Data32] = [:]

    // work package hash => segment root
    private var segmentRootByWorkPackageHash: [Data32: Data32] = [:]

    // erasure root + index => segment data
    private var chunks: [Data32: [UInt16: Data4104]] = [:]

    public init() {}
}

extension InMemoryDataStoreBackend: DataStoreProtocol {
    public func getEasureRoot(forSegmentRoot: Data32) async throws -> Data32? {
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
}

extension InMemoryDataStoreBackend: DataStoreNetworkProtocol {
    public func fetchRemoteChunk(erasureRoot _: Data32, shardIndex _: UInt16, segmentIndices _: [UInt16]) async throws -> Data12? {
        nil
    }
}
