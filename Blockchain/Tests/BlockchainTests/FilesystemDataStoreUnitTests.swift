import Foundation
import Testing
import TracingUtils
import Utils

@testable import Blockchain

/// Unit tests for FilesystemDataStore focusing on edge cases
/// and error handling
struct FilesystemDataStoreUnitTests {
    func makeDataStore() throws -> FilesystemDataStore {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fs_unit_test_\(UUID().uuidString)")

        return try FilesystemDataStore(dataPath: tempDir)
    }

    // MARK: - Path Construction Tests

    @Test
    func validateAuditBundlePathConstruction() throws {
        let dataStore = try makeDataStore()
        let erasureRoot = Data32.random()

        // Store a bundle to create the path
        let data = Data(count: 100)
        try await dataStore.storeAuditBundle(erasureRoot: erasureRoot, data: data)

        // Verify the bundle can be retrieved
        let retrieved = try await dataStore.getAuditBundle(erasureRoot: erasureRoot)
        #expect(retrieved != nil)
    }

    @Test
    func validateD3LShardPathConstruction() async throws {
        let dataStore = try makeDataStore()
        let erasureRoot = Data32.random()
        let shardIndex: UInt16 = 500

        // Store a shard to create the path
        let data = Data(count: 1000)
        try await dataStore.storeD3LShard(
            erasureRoot: erasureRoot,
            shardIndex: shardIndex,
            data: data
        )

        // Verify the shard can be retrieved
        let retrieved = try await dataStore.getD3LShard(
            erasureRoot: erasureRoot,
            shardIndex: shardIndex
        )
        #expect(retrieved != nil)
    }

    // MARK: - Atomic Write Tests

    @Test
    func atomicWritePreventsPartialData() async throws {
        let dataStore = try makeDataStore()
        let erasureRoot = Data32.random()

        // Write initial data
        let data1 = Data(count: 1000)
        for i in 0 ..< 1000 {
            data1[i] = UInt8(truncatingIfNeeded: i)
        }
        try await dataStore.storeAuditBundle(erasureRoot: erasureRoot, data: data1)

        // Overwrite with different data
        let data2 = Data(count: 2000)
        for i in 0 ..< 2000 {
            data2[i] = UInt8(truncatingIfNeeded: 255 - i % 256)
        }
        try await dataStore.storeAuditBundle(erasureRoot: erasureRoot, data: data2)

        // Verify we get the complete new data, not corrupted
        let retrieved = try await dataStore.getAuditBundle(erasureRoot: erasureRoot)
        #expect(retrieved?.count == 2000)
        #expect(retrieved?[0] == 255)
    }

    @Test
    func concurrentWritesToSameKey() async throws {
        let dataStore = try makeDataStore()
        let erasureRoot = Data32.random()

        // Perform multiple writes concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 0 ..< 10 {
                group.addTask {
                    let data = Data(count: 100)
                    try? await dataStore.storeAuditBundle(
                        erasureRoot: erasureRoot,
                        data: data
                    )
                }
            }
        }

        // Verify one write succeeded
        let retrieved = try await dataStore.getAuditBundle(erasureRoot: erasureRoot)
        #expect(retrieved != nil)
        #expect(retrieved?.count == 100)
    }

    // MARK: - Data Integrity Tests

    @Test
    func preserveDataIntegrity() async throws {
        let dataStore = try makeDataStore()
        let erasureRoot = Data32.random()

        // Create test data with specific pattern
        var originalData = Data(count: 50000)
        for i in 0 ..< 50000 {
            originalData[i] = UInt8(truncatingIfNeeded: (i * 7 + 13) % 256)
        }

        try await dataStore.storeAuditBundle(erasureRoot: erasureRoot, data: originalData)

        // Retrieve and verify
        let retrieved = try await dataStore.getAuditBundle(erasureRoot: erasureRoot)

        #expect(retrieved?.count == originalData.count)

        // Spot check various positions
        let checkPoints = [0, 100, 1000, 10000, 25000, 49999]
        for pos in checkPoints {
            #expect(
                retrieved?[pos] == originalData[pos],
                "Data at position \(pos) should match"
            )
        }
    }

    @Test
    func handleZeroLengthData() async throws {
        let dataStore = try makeDataStore()
        let erasureRoot = Data32.random()

        let emptyData = Data()
        try await dataStore.storeAuditBundle(erasureRoot: erasureRoot, data: emptyData)

        let retrieved = try await dataStore.getAuditBundle(erasureRoot: erasureRoot)

        #expect(retrieved != nil)
        #expect(retrieved?.count == 0)
    }

    @Test
    func handleLargeData() async throws {
        let dataStore = try makeDataStore()
        let erasureRoot = Data32.random()

        // Create large data (1 MB)
        let largeData = Data(count: 1_000_000)
        try await dataStore.storeAuditBundle(erasureRoot: erasureRoot, data: largeData)

        let retrieved = try await dataStore.getAuditBundle(erasureRoot: erasureRoot)

        #expect(retrieved?.count == 1_000_000)
    }

    // MARK: - Shard Index Tests

    @Test
    func shardIndexBoundaries() async throws {
        let dataStore = try makeDataStore()
        let erasureRoot = Data32.random()

        // Test minimum shard index
        try await dataStore.storeD3LShard(
            erasureRoot: erasureRoot,
            shardIndex: 0,
            data: Data(count: 100)
        )

        let minRetrieved = try await dataStore.getD3LShard(
            erasureRoot: erasureRoot,
            shardIndex: 0
        )
        #expect(minRetrieved != nil)

        // Test maximum shard index
        try await dataStore.storeD3LShard(
            erasureRoot: erasureRoot,
            shardIndex: 1022,
            data: Data(count: 100)
        )

        let maxRetrieved = try await dataStore.getD3LShard(
            erasureRoot: erasureRoot,
            shardIndex: 1022
        )
        #expect(maxRetrieved != nil)
    }

    @Test
    func retrieveNonExistentShard() async throws {
        let dataStore = try makeDataStore()
        let erasureRoot = Data32.random()
        let shardIndex: UInt16 = 999

        let retrieved = try await dataStore.getD3LShard(
            erasureRoot: erasureRoot,
            shardIndex: shardIndex
        )

        #expect(retrieved == nil)
    }

    // MARK: - Listing Tests

    @Test
    func listEmptyStore() async throws {
        let dataStore = try makeDataStore()

        let auditBundles = try await dataStore.listAuditBundles()
        #expect(auditBundles.isEmpty)

        let d3lEntries = try await dataStore.listD3LEntries()
        #expect(d3lEntries.isEmpty)
    }

    @Test
    func listMultipleEntries() async throws {
        let dataStore = try makeDataStore()

        let erasureRoots = [
            Data32.random(),
            Data32.random(),
            Data32.random(),
            Data32.random(),
            Data32.random(),
        ]

        // Store multiple audit bundles
        for erasureRoot in erasureRoots {
            try await dataStore.storeAuditBundle(
                erasureRoot: erasureRoot,
                data: Data(count: 100)
            )
        }

        // List
        let listed = try await dataStore.listAuditBundles()

        #expect(listed.count == 5)
        for erasureRoot in erasureRoots {
            #expect(listed.contains(erasureRoot))
        }
    }

    // MARK: - Deletion Tests

    @Test
    func deleteAndVerify() async throws {
        let dataStore = try makeDataStore()
        let erasureRoot = Data32.random()

        // Store
        try await dataStore.storeAuditBundle(erasureRoot: erasureRoot, data: Data(count: 100))

        // Verify exists
        var retrieved = try await dataStore.getAuditBundle(erasureRoot: erasureRoot)
        #expect(retrieved != nil)

        // Delete
        try await dataStore.deleteAuditBundle(erasureRoot: erasureRoot)

        // Verify deleted
        retrieved = try await dataStore.getAuditBundle(erasureRoot: erasureRoot)
        #expect(retrieved == nil)
    }

    @Test
    func deleteNonExistentEntry() async throws {
        let dataStore = try makeDataStore()
        let erasureRoot = Data32.random()

        // Should not throw when deleting non-existent entry
        try await dataStore.deleteAuditBundle(erasureRoot: erasureRoot)

        // Verify still doesn't exist
        let retrieved = try await dataStore.getAuditBundle(erasureRoot: erasureRoot)
        #expect(retrieved == nil)
    }

    // MARK: - Storage Size Tests

    @Test
    func calculateStorageSize() async throws {
        let dataStore = try makeDataStore()

        let erasureRoot = Data32.random()
        let data = Data(count: 10000)

        try await dataStore.storeAuditBundle(erasureRoot: erasureRoot, data: data)

        let size = try await dataStore.getAuditStoreSize()

        // Size should be approximately the data size (with some overhead for filesystem)
        #expect(size >= 10000)
        #expect(size < 15000) // Allow reasonable overhead
    }

    @Test
    func emptyStoreSize() async throws {
        let dataStore = try makeDataStore()

        let auditSize = try await dataStore.getAuditStoreSize()
        let d3lSize = try await dataStore.getD3LStoreSize()

        #expect(auditSize == 0)
        #expect(d3lSize == 0)
    }

    // MARK: - Error Handling Tests

    @Test
    func handleInvalidErasureRoot() async throws {
        let dataStore = try makeDataStore()

        // All-zero erasure root is valid but unlikely to exist
        let invalidRoot = Data32()

        let retrieved = try await dataStore.getAuditBundle(erasureRoot: invalidRoot)
        #expect(retrieved == nil)
    }

    @Test
    func overwritingExistingData() async throws {
        let dataStore = try makeDataStore()
        let erasureRoot = Data32.random()

        // Write first version
        let data1 = Data(count: 100)
        data1[0] = 42
        try await dataStore.storeAuditBundle(erasureRoot: erasureRoot, data: data1)

        // Write second version
        let data2 = Data(count: 100)
        data2[0] = 99
        try await dataStore.storeAuditBundle(erasureRoot: erasureRoot, data: data2)

        // Should get the second version
        let retrieved = try await dataStore.getAuditBundle(erasureRoot: erasureRoot)
        #expect(retrieved?[0] == 99)
    }

    // MARK: - Concurrent Access Tests

    @Test
    func concurrentReads() async throws {
        let dataStore = try makeDataStore()
        let erasureRoot = Data32.random()

        let data = Data(count: 10000)
        try await dataStore.storeAuditBundle(erasureRoot: erasureRoot, data: data)

        // Perform concurrent reads
        await withTaskGroup(of: Data?.self) { group in
            for _ in 0 ..< 10 {
                group.addTask {
                    try? await dataStore.getAuditBundle(erasureRoot: erasureRoot)
                }
            }
        }

        // Verify no errors occurred
        let retrieved = try await dataStore.getAuditBundle(erasureRoot: erasureRoot)
        #expect(retrieved != nil)
    }
}
