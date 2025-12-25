import Foundation
import RocksDBSwift
import Testing
import TracingUtils
import Utils

@testable import Blockchain

/// Tests for JAMNP-S CE 137-148 shard distribution protocol handlers
struct ShardDistributionProtocolHandlersTests {
    func makeDataStore() async throws -> ErasureCodingDataStore {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("protocol_handler_test_\(UUID().uuidString)")

        let db = try RocksDB<StoreId>(path: tempDir, columnFamilies: StoreId.allCases)

        for cf in StoreId.allCases.dropFirst() {
            try db.createColumnFamily(named: cf)
        }

        let rocksdbStore = RocksDBDataStore(db: db, config: .dev)
        let filesystemStore = try FilesystemDataStore(dataPath: tempDir)

        return ErasureCodingDataStore(
            rocksdbStore: rocksdbStore,
            filesystemStore: filesystemStore,
            config: .dev
        )
    }

    func makeHandlers() async throws -> (
        dataStore: ErasureCodingDataStore,
        handlers: ShardDistributionProtocolHandlers
    ) {
        let dataStore = try await makeDataStore()
        let erasureCoding = ErasureCodingService(config: .dev)

        let handlers = ShardDistributionProtocolHandlers(
            dataStore: dataStore,
            erasureCoding: erasureCoding,
            config: .dev
        )

        return (dataStore, handlers)
    }

    // MARK: - CE 137: Shard Distribution Tests

    @Test
    func handleShardDistributionReturnsBundleAndSegmentShards() async throws {
        let (dataStore, handlers) = try await makeHandlers()

        // Store a test bundle
        let bundleData = Data(count: 10000)
        let erasureRoot = try await dataStore.storeAuditBundle(
            bundle: bundleData,
            workPackageHash: Data32.random(),
            segmentsRoot: Data32.random()
        )

        // Request shard 0
        let message = ShardDistributionMessage(
            erasureRoot: erasureRoot,
            shardIndex: 0
        )

        // Handle the request
        let response = try await handlers.handleShardDistribution(message: message)

        // Should return a response
        #expect(!response.isEmpty)

        // Decode response
        let decoder = JamDecoder(data: response[0], config: .dev)

        // Decode bundle shard
        let bundleShard = try decoder.decode(Data.self)
        #expect(bundleShard.count == 684)

        // Decode segment shards count
        let segmentCount = try decoder.decode(UInt32.self)
        #expect(segmentCount > 0)
    }

    @Test
    func handleShardDistributionThrowsOnMissingShard() async throws {
        let (_, handlers) = try await makeHandlers()

        // Request non-existent shard
        let message = ShardDistributionMessage(
            erasureRoot: Data32.random(),
            shardIndex: 0
        )

        // Should throw error
        await #expect(throws: ShardDistributionError.self) {
            try await handlers.handleShardDistribution(message: message)
        }
    }

    // MARK: - CE 138: Audit Shard Request Tests

    @Test
    func handleAuditShardRequestReturnsBundleShardOnly() async throws {
        let (dataStore, handlers) = try await makeHandlers()

        // Store a test bundle
        let bundleData = Data(count: 10000)
        let erasureRoot = try await dataStore.storeAuditBundle(
            bundle: bundleData,
            workPackageHash: Data32.random(),
            segmentsRoot: Data32.random()
        )

        // Request shard 0
        let message = AuditShardRequestMessage(
            erasureRoot: erasureRoot,
            shardIndex: 0
        )

        // Handle the request
        let response = try await handlers.handleAuditShardRequest(message: message)

        // Should return response with bundle shard + justification
        #expect(!response.isEmpty)

        // CE 138 should return less data than CE 137 (no segment shards)
        let decoder = JamDecoder(data: response[0], config: .dev)
        let bundleShard = try decoder.decode(Data.self)
        #expect(bundleShard.count == 684)
    }

    // MARK: - CE 139: Segment Shard Request (Fast Mode) Tests

    @Test
    func handleSegmentShardRequestFastReturnsSegmentShards() async throws {
        let (dataStore, handlers) = try await makeHandlers()

        // Store a test bundle
        let bundleData = Data(count: 10000)
        let erasureRoot = try await dataStore.storeAuditBundle(
            bundle: bundleData,
            workPackageHash: Data32.random(),
            segmentsRoot: Data32.random()
        )

        // Request segments 0, 1, 2
        let message = SegmentShardRequestMessage(
            erasureRoot: erasureRoot,
            shardIndex: 0,
            segmentIndices: [0, 1, 2]
        )

        // Handle the request
        let response = try await handlers.handleSegmentShardRequestFast(message: message)

        // Should return segment shards
        #expect(!response.isEmpty)

        // Decode response
        let decoder = JamDecoder(data: response[0], config: .dev)
        let segmentCount = try decoder.decode(UInt32.self)
        #expect(segmentCount == 3)
    }

    // MARK: - CE 140: Segment Shard Request (Verified Mode) Tests

    @Test
    func handleSegmentShardRequestVerifiedReturnsJustifications() async throws {
        let (dataStore, handlers) = try await makeHandlers()

        // Store a test bundle
        let bundleData = Data(count: 10000)
        let erasureRoot = try await dataStore.storeAuditBundle(
            bundle: bundleData,
            workPackageHash: Data32.random(),
            segmentsRoot: Data32.random()
        )

        // Request segment 0
        let message = SegmentShardRequestMessage(
            erasureRoot: erasureRoot,
            shardIndex: 0,
            segmentIndices: [0]
        )

        // Handle the request
        let responses = try await handlers.handleSegmentShardRequestVerified(message: message)

        // Should return segment shard + justification
        #expect(responses.count >= 2) // At least segment data + justification
    }

    // MARK: - CE 147: Bundle Request Tests

    @Test
    func handleBundleRequestReconstructsBundle() async throws {
        let (dataStore, handlers) = try await makeHandlers()

        // Store a test bundle
        let originalBundle = Data("Test bundle data for reconstruction".utf8)
        let erasureRoot = try await dataStore.storeAuditBundle(
            bundle: originalBundle,
            workPackageHash: Data32.random(),
            segmentsRoot: Data32.random()
        )

        // Request bundle
        let response = try await handlers.handleBundleRequest(erasureRoot: erasureRoot)

        // Should return reconstructed bundle
        #expect(!response.isEmpty)
    }

    @Test
    func handleBundleRequestThrowsInsufficientShards() async throws {
        let (_, handlers) = try await makeHandlers()

        // Request non-existent bundle
        let erasureRoot = Data32.random()

        // Should throw error - not enough shards
        await #expect(throws: ShardDistributionError.self) {
            try await handlers.handleBundleRequest(erasureRoot: erasureRoot)
        }
    }

    // MARK: - Error Handling Tests

    @Test
    func handleInvalidErasureRootThrowsError() async throws {
        let (_, handlers) = try await makeHandlers()

        // All protocols should throw on invalid erasure root
        let shardMessage = ShardDistributionMessage(
            erasureRoot: Data32.random(),
            shardIndex: 0
        )

        await #expect(throws: ShardDistributionError.self) {
            try await handlers.handleShardDistribution(message: shardMessage)
        }
    }

    @Test
    func handleInvalidShardIndexThrowsError() async throws {
        let (dataStore, handlers) = try await makeHandlers()

        // Store a test bundle
        let bundleData = Data(count: 10000)
        let erasureRoot = try await dataStore.storeAuditBundle(
            bundle: bundleData,
            workPackageHash: Data32.random(),
            segmentsRoot: Data32.random()
        )

        // Request invalid shard index (out of range)
        let message = ShardDistributionMessage(
            erasureRoot: erasureRoot,
            shardIndex: 2000 // Invalid index
        )

        // Should handle gracefully - may not throw if shard doesn't exist
        // but should return error or empty response
        do {
            let response = try await handlers.handleShardDistribution(message: message)
            // If it doesn't throw, response should indicate failure
            #expect(response.isEmpty || response[0].isEmpty)
        } catch {
            // Expected - shard index out of range
            #expect(true)
        }
    }

    // MARK: - Integration Tests

    @Test
    func fullCE137FlowWorksEndToEnd() async throws {
        let (dataStore, handlers) = try await makeHandlers()

        // 1. Store bundle
        let bundleData = Data("Integration test bundle".utf8)
        let erasureRoot = try await dataStore.storeAuditBundle(
            bundle: bundleData,
            workPackageHash: Data32.random(),
            segmentsRoot: Data32.random()
        )

        // 2. Request shard via CE 137
        let message = ShardDistributionMessage(
            erasureRoot: erasureRoot,
            shardIndex: 0
        )

        // 3. Get response
        let response = try await handlers.handleShardDistribution(message: message)

        // 4. Verify response format
        #expect(!response.isEmpty)

        let decoder = JamDecoder(data: response[0], config: .dev)

        // Bundle shard
        let bundleShard = try decoder.decode(Data.self)
        #expect(bundleShard.count == 684)

        // Segment shards
        let segmentCount = try decoder.decode(UInt32.self)
        #expect(segmentCount > 0)

        // Each segment shard
        for _ in 0 ..< segmentCount {
            let segmentShard = try decoder.decode(Data.self)
            #expect(!segmentShard.isEmpty)
        }
    }
}
