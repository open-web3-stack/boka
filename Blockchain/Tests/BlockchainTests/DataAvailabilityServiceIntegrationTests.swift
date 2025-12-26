import Foundation
import Testing
import TracingUtils
import Utils

@testable import Blockchain

struct DataAvailabilityServiceIntegrationTests {
    func makeService() async throws -> (DataAvailabilityService, ErasureCodingDataStore) {
        // Create temporary directory for filesystem store
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("da_integration_test_\(UUID().uuidString)")

        // Use in-memory data store instead of RocksDB
        let inMemoryStore = InMemoryDataStore()
        let filesystemStore = try FilesystemDataStore(dataPath: tempDir)

        let erasureCodingDataStore = ErasureCodingDataStore(
            dataStore: inMemoryStore,
            filesystemStore: filesystemStore,
            config: .dev
        )

        // Create a mock data provider
        let mockDataProvider = MockBlockchainDataProvider()

        // Create the service with ErasureCodingDataStore
        let service = DataAvailabilityService(
            config: .dev,
            eventBus: EventBus(),
            scheduler: Scheduler(),
            dataProvider: mockDataProvider,
            dataStore: inMemoryStore,
            erasureCodingDataStore: erasureCodingDataStore
        )

        return (service, erasureCodingDataStore)
    }

    // MARK: - Audit Bundle Tests

    @Test
    func exportAndRetrieveAuditBundle() async throws {
        let (service, _) = try await makeService()

        // Create a test work package bundle
        let workPackage = WorkPackage(
            coreIndex: 0,
            coreSlot: 0,
            authorityIndex: 0,
            authorityProof: Data(),
            bundle: .extrinsics([])
        )

        let bundle = WorkPackageBundle(
            workPackage: workPackage,
            extrinsics: [],
            proofs: [],
            importedDataSegments: []
        )

        // Export the bundle
        let result = try await service.exportWorkpackageBundle(bundle: bundle)

        // Verify erasure root was returned
        #expect(result.erasureRoot != Data32())
        #expect(result.length > 0)

        // Retrieve the bundle
        let retrieved = try await service.retrieveAuditBundle(erasureRoot: result.erasureRoot)

        #expect(retrieved != nil)
        #expect(retrieved?.count > 0)
    }

    @Test
    func exportLargeAuditBundle() async throws {
        let (service, _) = try await makeService()

        // Create a large bundle
        var extrinsics: [Extrinsic] = []
        for _ in 0 ..< 100 {
            extrinsics.append(Extrinsic(
                signature: Data(),
                signed: .extrinsic(Data())
            ))
        }

        let workPackage = WorkPackage(
            coreIndex: 0,
            coreSlot: 0,
            authorityIndex: 0,
            authorityProof: Data(),
            bundle: .extrinsics(extrinsics)
        )

        let bundle = WorkPackageBundle(
            workPackage: workPackage,
            extrinsics: extrinsics,
            proofs: [],
            importedDataSegments: []
        )

        // Should handle large bundles
        let result = try await service.exportWorkpackageBundle(bundle: bundle)

        #expect(result.erasureRoot != Data32())
        #expect(result.length > 0)
    }

    @Test
    func exportSegmentsToD3LStore() async throws {
        let (service, _) = try await makeService()

        // Create test segments
        var segments: [Data4104] = []
        for i in 0 ..< 10 {
            var segmentData = Data(count: 4104)
            segmentData[0] = UInt8(truncatingIfNeeded: i)
            segments.append(Data4104(segmentData)!)
        }

        let erasureRoot = Data32.random()

        // Export segments
        let segmentRoot = try await service.exportSegments(data: segments, erasureRoot: erasureRoot)

        #expect(segmentRoot != Data32())
    }

    // MARK: - Cleanup Tests

    @Test
    func purgeOldAuditEntries() async throws {
        let (service, ecStore) = try await makeService()

        // Store an audit bundle
        let workPackage = WorkPackage(
            coreIndex: 0,
            coreSlot: 0,
            authorityIndex: 0,
            authorityProof: Data(),
            bundle: .extrinsics([])
        )

        let bundle = WorkPackageBundle(
            workPackage: workPackage,
            extrinsics: [],
            proofs: [],
            importedDataSegments: []
        )

        let result = try await service.exportWorkpackageBundle(bundle: bundle)

        // Manually set old timestamp
        try await ecStore.dataStore.setTimestamp(
            erasureRoot: result.erasureRoot,
            timestamp: Date().addingTimeInterval(-10000)
        )

        // Trigger purge
        await service.purge(epoch: 100)

        // Entry should be cleaned up (but we can't easily verify this without more methods)
    }

    @Test
    func statisticsAfterOperations() async throws {
        let (service, _) = try await makeService()

        // Export an audit bundle
        let workPackage = WorkPackage(
            coreIndex: 0,
            coreSlot: 0,
            authorityIndex: 0,
            authorityProof: Data(),
            bundle: .extrinsics([])
        )

        let bundle = WorkPackageBundle(
            workPackage: workPackage,
            extrinsics: [],
            proofs: [],
            importedDataSegments: []
        )

        _ = try await service.exportWorkpackageBundle(bundle: bundle)

        // Get statistics
        let stats = await service.getStatistics()

        #expect(stats.auditStoreCount >= 0)
        #expect(stats.importStoreCount >= 0)
        #expect(stats.totalSegments >= 0)
    }

    // MARK: - Reconstruction Tests

    @Test
    func reconstructDataFromShards() async throws {
        let (service, _) = try await makeService()

        // Create test data
        let originalData = Data(count: 684 * 10)
        var testData = originalData
        for i in 0 ..< testData.count {
            testData[i] = UInt8(truncatingIfNeeded: i % 256)
        }

        // Encode using ErasureCoding
        let shards = try ErasureCoding.chunk(
            data: testData,
            basicSize: 684,
            recoveryCount: 1023
        )

        // Take only 400 shards (more than minimum 342)
        let partialShards = Array(shards.prefix(400))
        let shardTuples = partialShards.enumerated().map { index, data in
            (index: UInt16(index), data: data)
        }

        // Reconstruct
        let reconstructed = try await service.reconstructData(
            shards: shardTuples,
            originalLength: testData.count
        )

        #expect(reconstructed.count == testData.count)
        #expect(reconstructed == testData)
    }

    @Test
    func reconstructFromInsufficientShardsThrowsError() async throws {
        let (service, _) = try await makeService()

        // Create test data
        let testData = Data(count: 684 * 10)

        // Encode using ErasureCoding
        let shards = try ErasureCoding.chunk(
            data: testData,
            basicSize: 684,
            recoveryCount: 1023
        )

        // Take only 300 shards (insufficient)
        let partialShards = Array(shards.prefix(300))
        let shardTuples = partialShards.enumerated().map { index, data in
            (index: UInt16(index), data: data)
        }

        // Should throw error
        #expect(throws: DataAvailabilityError.self) {
            try await service.reconstructData(
                shards: shardTuples,
                originalLength: testData.count
            )
        }
    }

    // MARK: - Health Check Tests

    @Test
    func healthCheckReturnsTrue() async throws {
        let (service, _) = try await makeService()

        let isHealthy = await service.healthCheck()

        #expect(isHealthy)
    }

    // MARK: - Mock Data Provider

    class MockBlockchainDataProvider: BlockchainDataProvider {
        var bestHead: BlockHeader = .init(
            parentHash: Data32(),
            number: 0,
            stateRoot: Data32(),
            extrinsicsRoot: Data32(),
            digest: Data(),
            workReportsHash: Data32(),
            timeslot: 0
        )

        func getHeader(hash _: Data32) async throws -> BlockHeader {
            bestHead
        }

        func getBlock(hash _: Data32) async throws -> Block {
            fatalError("Not implemented for mock")
        }

        func getState(hash _: Data32) async throws -> StateRef {
            fatalError("Not implemented for mock")
        }

        func getHeader(blockNumber _: UInt32) async throws -> BlockHeader {
            bestHead
        }

        func add(guaranteedWorkReport _: GuaranteedWorkReportRef) async throws {
            // Mock implementation
        }

        func finalize(header _: BlockHeader, justifications _: [Data32: Justification]) async throws {
            // Mock implementation
        }

        func add(body _: Block.Body, to _: Data32) async throws {
            // Mock implementation
        }
    }
}
