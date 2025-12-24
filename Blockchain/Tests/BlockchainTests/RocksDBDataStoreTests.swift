import Foundation
import RocksDBSwift
import Testing
import TracingUtils
import Utils

@testable import Blockchain

struct RocksDBDataStoreTests {
    func makeDataStore() async throws -> RocksDBDataStore {
        // Create temporary directory for test
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rocksdb_test_\(UUID().uuidString)")

        // Create RocksDB instance
        let db = try RocksDB<StoreId>(path: tempDir, columnFamilies: StoreId.allCases)

        // Initialize column families
        for cf in StoreId.allCases.dropFirst() {
            // Skip 'meta' as it's already created
            try db.createColumnFamily(named: cf)
        }

        return RocksDBDataStore(db: db, config: .dev)
    }

    // MARK: - Basic CRUD Tests

    @Test
    func setAndGetSegment() async throws {
        let dataStore = try await makeDataStore()

        let erasureRoot = Data32.random()
        let index: UInt16 = 0
        var data = Data4104()
        data[0] = 42
        data[100] = 99

        // Store
        try await dataStore.set(data: data, erasureRoot: erasureRoot, index: index)

        // Retrieve
        let retrieved = try await dataStore.get(erasureRoot: erasureRoot, index: index)

        #expect(retrieved != nil)
        #expect(retrieved?[0] == 42)
        #expect(retrieved?[100] == 99)
    }

    @Test
    func getNonExistentSegmentReturnsNil() async throws {
        let dataStore = try await makeDataStore()

        let erasureRoot = Data32.random()
        let index: UInt16 = 0

        let retrieved = try await dataStore.get(erasureRoot: erasureRoot, index: index)

        #expect(retrieved == nil)
    }

    @Test
    func setAndGetTimestamp() async throws {
        let dataStore = try await makeDataStore()

        let erasureRoot = Data32.random()
        let timestamp = Date()

        // Set timestamp
        try await dataStore.setTimestamp(erasureRoot: erasureRoot, timestamp: timestamp)

        // Get timestamp
        let retrieved = try await dataStore.getTimestamp(erasureRoot: erasureRoot)

        #expect(retrieved != nil)
        // Allow small difference due to rounding
        let timeDiff = abs(retrieved!.timeIntervalSince(timestamp))
        #expect(timeDiff < 1.0)
    }

    @Test
    func setAndGetPagedProofsMetadata() async throws {
        let dataStore = try await makeDataStore()

        let erasureRoot = Data32.random()
        var metadata = Data(count: 100)
        for i in 0 ..< 100 {
            metadata[i] = UInt8(truncatingIfNeeded: i)
        }

        // Set metadata
        try await dataStore.setPagedProofsMetadata(erasureRoot: erasureRoot, metadata: metadata)

        // Get metadata
        let retrieved = try await dataStore.getPagedProofsMetadata(erasureRoot: erasureRoot)

        #expect(retrieved != nil)
        #expect(retrieved?.count == 100)
        #expect(retrieved?[0] == 0)
        #expect(retrieved?[99] == 99)
    }

    // MARK: - Mapping Tests

    @Test
    func setAndGetSegmentRootMapping() async throws {
        let dataStore = try await makeDataStore()

        let workPackageHash = Data32.random()
        let segmentsRoot = Data32.random()

        // Set mapping
        try await dataStore.set(segmentRoot: segmentsRoot, forWorkPackageHash: workPackageHash)

        // Get mapping
        let retrieved = try await dataStore.getSegmentRoot(forWorkPackageHash: workPackageHash)

        #expect(retrieved != nil)
        #expect(retrieved == segmentsRoot)
    }

    @Test
    func setAndGetErasureRootMapping() async throws {
        let dataStore = try await makeDataStore()

        let segmentRoot = Data32.random()
        let erasureRoot = Data32.random()

        // Set mapping
        try await dataStore.set(erasureRoot: erasureRoot, forSegmentRoot: segmentRoot)

        // Get mapping
        let retrieved = try await dataStore.getErasureRoot(forSegmentRoot: segmentRoot)

        #expect(retrieved != nil)
        #expect(retrieved == erasureRoot)
    }

    // MARK: - Shard Operations Tests

    @Test
    func storeAndGetShard() async throws {
        let dataStore = try await makeDataStore()

        let erasureRoot = Data32.random()
        let shardIndex: UInt16 = 100
        var shardData = Data(count: 500)
        for i in 0 ..< 500 {
            shardData[i] = UInt8(truncatingIfNeeded: i)
        }

        // Store shard
        try await dataStore.storeShard(shardData: shardData, erasureRoot: erasureRoot, shardIndex: shardIndex)

        // Get shard
        let retrieved = try await dataStore.getShard(erasureRoot: erasureRoot, shardIndex: shardIndex)

        #expect(retrieved != nil)
        #expect(retrieved?.count == 500)
        #expect(retrieved?[0] == 0)
        #expect(retrieved?[499] == 243) // 499 % 256
    }

    @Test
    func storeAndGetShards() async throws {
        let dataStore = try await makeDataStore()

        let erasureRoot = Data32.random()
        var shards: [(index: UInt16, data: Data)] = []

        for i in 0 ..< 10 {
            var data = Data(count: 100)
            data[0] = UInt8(truncatingIfNeeded: i)
            shards.append((index: UInt16(i), data: data))
        }

        // Store shards
        try await dataStore.storeShards(shards: shards, erasureRoot: erasureRoot)

        // Get shards
        let indices = shards.map(\.index)
        let retrieved = try await dataStore.getShards(erasureRoot: erasureRoot, shardIndices: indices)

        #expect(retrieved.count == 10)

        for (i, shard) in retrieved.enumerated() {
            #expect(shard.index == UInt16(i))
            #expect(shard.data[0] == UInt8(i))
        }
    }

    @Test
    func getShardCount() async throws {
        let dataStore = try await makeDataStore()

        let erasureRoot = Data32.random()
        var shards: [(index: UInt16, data: Data)] = []

        // Store 50 shards
        for i in 0 ..< 50 {
            let data = Data(count: 100)
            shards.append((index: UInt16(i), data: data))
        }

        try await dataStore.storeShards(shards: shards, erasureRoot: erasureRoot)

        // Get count
        let count = try await dataStore.getShardCount(erasureRoot: erasureRoot)

        #expect(count == 50)
    }

    @Test
    func canReconstruct() async throws {
        let dataStore = try await makeDataStore()

        let erasureRoot = Data32.random()
        var shards: [(index: UInt16, data: Data)] = []

        // Store 400 shards (more than 342 needed)
        for i in 0 ..< 400 {
            let data = Data(count: 100)
            shards.append((index: UInt16(i), data: data))
        }

        try await dataStore.storeShards(shards: shards, erasureRoot: erasureRoot)

        // Check if can reconstruct
        let canReconstruct = try await dataStore.canReconstruct(erasureRoot: erasureRoot)

        #expect(canReconstruct == true)
    }

    @Test
    func cannotReconstructWithInsufficientShards() async throws {
        let dataStore = try await makeDataStore()

        let erasureRoot = Data32.random()
        var shards: [(index: UInt16, data: Data)] = []

        // Store only 300 shards (less than 342 needed)
        for i in 0 ..< 300 {
            let data = Data(count: 100)
            shards.append((index: UInt16(i), data: data))
        }

        try await dataStore.storeShards(shards: shards, erasureRoot: erasureRoot)

        // Check if can reconstruct
        let canReconstruct = try await dataStore.canReconstruct(erasureRoot: erasureRoot)

        #expect(canReconstruct == false)
    }

    @Test
    func getAvailableShardIndices() async throws {
        let dataStore = try await makeDataStore()

        let erasureRoot = Data32.random()
        var shards: [(index: UInt16, data: Data)] = []

        // Store specific shards
        let indices: [UInt16] = [0, 10, 100, 500, 1000]
        for index in indices {
            let data = Data(count: 100)
            shards.append((index: index, data: data))
        }

        try await dataStore.storeShards(shards: shards, erasureRoot: erasureRoot)

        // Get available indices
        let availableIndices = try await dataStore.getAvailableShardIndices(erasureRoot: erasureRoot)

        #expect(availableIndices.count == 5)
        #expect(availableIndices.sorted() == indices.sorted())
    }

    @Test
    func deleteShards() async throws {
        let dataStore = try await makeDataStore()

        let erasureRoot = Data32.random()
        var shards: [(index: UInt16, data: Data)] = []

        // Store shards
        for i in 0 ..< 50 {
            let data = Data(count: 100)
            shards.append((index: UInt16(i), data: data))
        }

        try await dataStore.storeShards(shards: shards, erasureRoot: erasureRoot)

        // Verify stored
        let countBefore = try await dataStore.getShardCount(erasureRoot: erasureRoot)
        #expect(countBefore == 50)

        // Delete shards
        try await dataStore.deleteShards(erasureRoot: erasureRoot)

        // Verify deleted
        let countAfter = try await dataStore.getShardCount(erasureRoot: erasureRoot)
        #expect(countAfter == 0)
    }

    // MARK: - Audit Entry Tests

    @Test
    func setAndGetAuditEntry() async throws {
        let dataStore = try await makeDataStore()

        let workPackageHash = Data32.random()
        let erasureRoot = Data32.random()
        let bundleSize = 13_500_000
        let timestamp = Date()

        let entry = AuditEntry(
            workPackageHash: workPackageHash,
            erasureRoot: erasureRoot,
            bundleSize: bundleSize,
            timestamp: timestamp
        )

        // Store
        try await dataStore.setAuditEntry(
            workPackageHash: workPackageHash,
            erasureRoot: erasureRoot,
            bundleSize: bundleSize,
            timestamp: timestamp
        )

        // Retrieve
        let retrieved = try await dataStore.getAuditEntry(erasureRoot: erasureRoot)

        #expect(retrieved != nil)
        #expect(retrieved?.workPackageHash == workPackageHash)
        #expect(retrieved?.erasureRoot == erasureRoot)
        #expect(retrieved?.bundleSize == bundleSize)
    }

    @Test
    func listAuditEntriesBefore() async throws {
        let dataStore = try await makeDataStore()

        let now = Date()
        let oldTimestamp = now.addingTimeInterval(-1000)
        let newTimestamp = now.addingTimeInterval(1000)

        // Store old entry
        try await dataStore.setAuditEntry(
            workPackageHash: Data32.random(),
            erasureRoot: Data32.random(),
            bundleSize: 1000,
            timestamp: oldTimestamp
        )

        // Store new entry
        try await dataStore.setAuditEntry(
            workPackageHash: Data32.random(),
            erasureRoot: Data32.random(),
            bundleSize: 2000,
            timestamp: newTimestamp
        )

        // List entries before now
        let entries = try await dataStore.listAuditEntries(before: now)

        // Should only find the old entry
        #expect(entries.count == 1)
        #expect(entries[0].bundleSize == 1000)
    }

    // MARK: - D³L Entry Tests

    @Test
    func setAndGetD3LEntry() async throws {
        let dataStore = try await makeDataStore()

        let segmentsRoot = Data32.random()
        let erasureRoot = Data32.random()
        let segmentCount: UInt32 = 100
        let timestamp = Date()

        // Store
        try await dataStore.setD3LEntry(
            segmentsRoot: segmentsRoot,
            erasureRoot: erasureRoot,
            segmentCount: segmentCount,
            timestamp: timestamp
        )

        // Retrieve
        let retrieved = try await dataStore.getD3LEntry(erasureRoot: erasureRoot)

        #expect(retrieved != nil)
        #expect(retrieved?.segmentsRoot == segmentsRoot)
        #expect(retrieved?.segmentCount == segmentCount)
    }

    // MARK: - Statistics Tests

    @Test
    func getStatistics() async throws {
        let dataStore = try await makeDataStore()

        // Store some audit entries
        for _ in 0 ..< 5 {
            try await dataStore.setAuditEntry(
                workPackageHash: Data32.random(),
                erasureRoot: Data32.random(),
                bundleSize: 1000,
                timestamp: Date()
            )
        }

        // Store some D³L entries
        for i in 0 ..< 3 {
            try await dataStore.setD3LEntry(
                segmentsRoot: Data32.random(),
                erasureRoot: Data32.random(),
                segmentCount: UInt32((i + 1) * 10),
                timestamp: Date()
            )
        }

        // Get statistics
        let stats = try await dataStore.getStatistics()

        #expect(stats.auditCount == 5)
        #expect(stats.d3lCount == 3)
        #expect(stats.totalSegments == 60) // 10 + 20 + 30
    }
}
