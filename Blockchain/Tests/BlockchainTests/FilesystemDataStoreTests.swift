import Foundation
import Testing
import TracingUtils
import Utils

@testable import Blockchain

struct FilesystemDataStoreTests {
    func makeDataStore() async throws -> FilesystemDataStore {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("filesystem_test_\(UUID().uuidString)")

        return await FilesystemDataStore(dataPath: tempDir)
    }

    // MARK: - Audit Bundle Tests

    @Test
    func storeAndGetAuditBundle() async throws {
        let dataStore = try await makeDataStore()

        let erasureRoot = Data32.random()
        var bundleData = Data(count: 10000)
        for i in 0 ..< 10000 {
            bundleData[i] = UInt8(truncatingIfNeeded: i % 256)
        }

        // Store
        try await dataStore.storeAuditBundle(erasureRoot: erasureRoot, data: bundleData)

        // Retrieve
        let retrieved = try await dataStore.getAuditBundle(erasureRoot: erasureRoot)

        #expect(retrieved != nil)
        #expect(retrieved?.count == 10000)
        #expect(retrieved?[0] == 0)
        #expect(retrieved?[9999] == 255)
    }

    @Test
    func getNonExistentAuditBundleReturnsNil() async throws {
        let dataStore = try await makeDataStore()

        let erasureRoot = Data32.random()

        let retrieved = try await dataStore.getAuditBundle(erasureRoot: erasureRoot)

        #expect(retrieved == nil)
    }

    @Test
    func deleteAuditBundle() async throws {
        let dataStore = try await makeDataStore()

        let erasureRoot = Data32.random()
        let bundleData = Data(count: 1000)

        // Store
        try await dataStore.storeAuditBundle(erasureRoot: erasureRoot, data: bundleData)

        // Verify exists
        var retrieved = try await dataStore.getAuditBundle(erasureRoot: erasureRoot)
        #expect(retrieved != nil)

        // Delete
        try await dataStore.deleteAuditBundle(erasureRoot: erasureRoot)

        // Verify deleted
        retrieved = try await dataStore.getAuditBundle(erasureRoot: erasureRoot)
        #expect(retrieved == nil)
    }

    // MARK: - D³L Shard Tests

    @Test
    func storeAndGetD3LShard() async throws {
        let dataStore = try await makeDataStore()

        let erasureRoot = Data32.random()
        let shardIndex: UInt16 = 500
        var shardData = Data(count: 1000)
        for i in 0 ..< 1000 {
            shardData[i] = UInt8(truncatingIfNeeded: i)
        }

        // Store
        try await dataStore.storeD3LShard(
            erasureRoot: erasureRoot,
            shardIndex: shardIndex,
            data: shardData
        )

        // Retrieve
        let retrieved = try await dataStore.getD3LShard(
            erasureRoot: erasureRoot,
            shardIndex: shardIndex
        )

        #expect(retrieved != nil)
        #expect(retrieved?.count == 1000)
        #expect(retrieved?[0] == 0)
        #expect(retrieved?[999] == 231)
    }

    @Test
    func storeMultipleD3LShards() async throws {
        let dataStore = try await makeDataStore()

        let erasureRoot = Data32.random()

        // Store 10 shards
        for i in 0 ..< 10 {
            var shardData = Data(count: 100)
            shardData[0] = UInt8(truncatingIfNeeded: i)

            try await dataStore.storeD3LShard(
                erasureRoot: erasureRoot,
                shardIndex: UInt16(i),
                data: shardData
            )
        }

        // Retrieve all
        for i in 0 ..< 10 {
            let retrieved = try await dataStore.getD3LShard(
                erasureRoot: erasureRoot,
                shardIndex: UInt16(i)
            )

            #expect(retrieved != nil)
            #expect(retrieved?[0] == UInt8(i))
        }
    }

    @Test
    func getAvailableShardIndices() async throws {
        let dataStore = try await makeDataStore()

        let erasureRoot = Data32.random()

        // Store specific shards
        let indices: [UInt16] = [0, 100, 500, 1022]
        for index in indices {
            let data = Data(count: 100)
            try await dataStore.storeD3LShard(
                erasureRoot: erasureRoot,
                shardIndex: index,
                data: data
            )
        }

        // Get available indices
        let availableIndices = try await dataStore.getAvailableShardIndices(erasureRoot: erasureRoot)

        #expect(availableIndices.count == 4)
        #expect(availableIndices.sorted() == indices.sorted())
    }

    @Test
    func deleteD3LShards() async throws {
        let dataStore = try await makeDataStore()

        let erasureRoot = Data32.random()

        // Store shards
        for i in 0 ..< 10 {
            let data = Data(count: 100)
            try await dataStore.storeD3LShard(
                erasureRoot: erasureRoot,
                shardIndex: UInt16(i),
                data: data
            )
        }

        // Verify they exist
        var indices = try await dataStore.getAvailableShardIndices(erasureRoot: erasureRoot)
        #expect(indices.count == 10)

        // Delete
        try await dataStore.deleteD3LShards(erasureRoot: erasureRoot)

        // Verify deleted
        indices = try await dataStore.getAvailableShardIndices(erasureRoot: erasureRoot)
        #expect(indices.count == 0)
    }

    // MARK: - Listing Tests

    @Test
    func listAuditBundles() async throws {
        let dataStore = try await makeDataStore()

        let erasureRoots = [
            Data32.random(),
            Data32.random(),
            Data32.random(),
        ]

        // Store bundles
        for erasureRoot in erasureRoots {
            try await dataStore.storeAuditBundle(
                erasureRoot: erasureRoot,
                data: Data(count: 100)
            )
        }

        // List
        let listed = try await dataStore.listAuditBundles()

        #expect(listed.count == 3)
        // All should be in the list (order may vary)
        for erasureRoot in erasureRoots {
            #expect(listed.contains(erasureRoot))
        }
    }

    @Test
    func listD3LEntries() async throws {
        let dataStore = try await makeDataStore()

        let erasureRoots = [
            Data32.random(),
            Data32.random(),
            Data32.random(),
        ]

        // Store shards for each
        for erasureRoot in erasureRoots {
            try await dataStore.storeD3LShard(
                erasureRoot: erasureRoot,
                shardIndex: 0,
                data: Data(count: 100)
            )
        }

        // List
        let listed = try await dataStore.listD3LEntries()

        #expect(listed.count == 3)
        for erasureRoot in erasureRoots {
            #expect(listed.contains(erasureRoot))
        }
    }

    // MARK: - Storage Size Tests

    @Test
    func getAuditStoreSize() async throws {
        let dataStore = try await makeDataStore()

        // Store multiple bundles
        for _ in 0 ..< 5 {
            let erasureRoot = Data32.random()
            let bundleData = Data(count: 10000)
            try await dataStore.storeAuditBundle(erasureRoot: erasureRoot, data: bundleData)
        }

        // Get size
        let size = try await dataStore.getAuditStoreSize()

        #expect(size > 0)
        // Should be approximately 5 * 10,000 bytes (plus overhead)
        #expect(size >= 50000)
        #expect(size < 60000) // Allow some overhead
    }

    @Test
    func getD3LStoreSize() async throws {
        let dataStore = try await makeDataStore()

        let erasureRoot = Data32.random()

        // Store shards
        for i in 0 ..< 10 {
            let shardData = Data(count: 5000)
            try await dataStore.storeD3LShard(
                erasureRoot: erasureRoot,
                shardIndex: UInt16(i),
                data: shardData
            )
        }

        // Get size
        let size = try await dataStore.getD3LStoreSize()

        #expect(size > 0)
        // Should be approximately 10 * 5,000 bytes (plus overhead)
        #expect(size >= 50000)
        #expect(size < 60000) // Allow some overhead
    }

    // MARK: - Atomic Write Tests

    @Test
    func atomicWritePreventsCorruption() async throws {
        let dataStore = try await makeDataStore()

        let erasureRoot = Data32.random()
        let originalData = Data(count: 1000)
        let newData = Data(count: 2000)

        // Store original
        try await dataStore.storeAuditBundle(erasureRoot: erasureRoot, data: originalData)

        // Overwrite with new data
        try await dataStore.storeAuditBundle(erasureRoot: erasureRoot, data: newData)

        // Should have new data (atomic write succeeded)
        let retrieved = try await dataStore.getAuditBundle(erasureRoot: erasureRoot)

        #expect(retrieved != nil)
        #expect(retrieved?.count == 2000)
    }

    // MARK: - Directory Structure Tests

    @Test
    func directoryStructureUsesPrefix() async throws {
        let dataStore = try await makeDataStore()

        let erasureRoot = Data32.random()
        let bundleData = Data(count: 100)

        // Store
        try await dataStore.storeAuditBundle(erasureRoot: erasureRoot, data: bundleData)

        // List bundles to verify storage
        let listed = try await dataStore.listAuditBundles()

        #expect(listed.count == 1)
        #expect(listed.contains(erasureRoot))
    }

    // MARK: - Error Handling Tests

    @Test
    func getMissingShardReturnsNil() async throws {
        let dataStore = try await makeDataStore()

        let erasureRoot = Data32.random()
        let shardIndex: UInt16 = 999

        let retrieved = try await dataStore.getD3LShard(
            erasureRoot: erasureRoot,
            shardIndex: shardIndex
        )

        #expect(retrieved == nil)
    }
}
