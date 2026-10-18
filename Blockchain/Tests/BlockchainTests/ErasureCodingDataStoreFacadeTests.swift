@testable import Blockchain
import Foundation
import Testing
import Utils

@Suite(.serialized)
struct ErasureCodingDataStoreFacadeTests {
    private struct Fixture {
        let store: ErasureCodingDataStore
        let dataStore: InMemoryDataStore
        let filesystemStore: FilesystemDataStore
        let tempDir: URL
    }

    private func makeFixture() throws -> Fixture {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("erasure_coding_store_test_\(UUID().uuidString)")
        let dataStore = InMemoryDataStore()
        let filesystemStore = try FilesystemDataStore(dataPath: tempDir)
        let store = ErasureCodingDataStore(
            dataStore: dataStore,
            filesystemStore: filesystemStore,
            config: .dev,
        )
        return Fixture(
            store: store,
            dataStore: dataStore,
            filesystemStore: filesystemStore,
            tempDir: tempDir,
        )
    }

    private func removeFixtureDirectory(_ fixture: Fixture) {
        try? FileManager.default.removeItem(at: fixture.tempDir)
    }

    @Test
    func completeBundleDoesNotRequireCodingMetadata() async throws {
        let fixture = try makeFixture()
        defer { removeFixtureDirectory(fixture) }
        let root = data32(91)
        let bundle = Data([1, 2, 3])
        try await fixture.filesystemStore.storeAuditBundle(erasureRoot: root, data: bundle)
        #expect(try await fixture.store.getAuditBundle(erasureRoot: root) == bundle)
    }

    @Test
    func auditBundleLimitUsesTheActiveConfiguration() async throws {
        let fixture = try makeFixture()
        defer { removeFixtureDirectory(fixture) }
        let config = ProtocolConfigRef.dev.mutate {
            $0.maxEncodedWorkPackageSize = 16
            $0.maxWorkPackageImports = 0
            $0.maxWorkPackageExtrinsics = 0
            $0.maxDepsInWorkReport = 0
            $0.maxWorkItems = 1
        }
        let store = ErasureCodingDataStore(dataStore: fixture.dataStore, filesystemStore: fixture.filesystemStore, config: config)
        await #expect(throws: ErasureCodingStoreError.self) {
            try await store.storeAuditBundle(bundle: Data(count: config.value.maxWorkBundleSize + 1), workPackageHash: data32(92), segmentsRoot: data32(93))
        }
        _ = try await store.storeAuditBundle(bundle: Data(count: config.value.maxWorkBundleSize), workPackageHash: data32(92), segmentsRoot: data32(93))
    }

    @Test(arguments: [false, true])
    func cleanupKeepsSharedCodingCountUntilBothStoresExpire(iterative: Bool) async throws {
        let fixture = try makeFixture()
        defer { removeFixtureDirectory(fixture) }
        let root = data32(94)
        let old = Date(timeIntervalSince1970: 0)
        try await fixture.dataStore.setErasureValidatorCount(erasureRoot: root, count: 6)
        try await fixture.dataStore.setAuditEntry(workPackageHash: data32(95), erasureRoot: root, segmentsRoot: data32(96), bundleSize: 6, timestamp: old)
        try await fixture.dataStore.setD3LEntry(segmentsRoot: data32(96), erasureRoot: root, segmentCount: 1, timestamp: old)
        let cleanup = DataStoreCleanup(dataStore: fixture.dataStore, filesystemStore: fixture.filesystemStore)
        if iterative {
            _ = try await cleanup.cleanupAuditEntries(retentionEpochs: 0)
        } else {
            _ = try await cleanup.cleanupAuditEntriesBeforeEpoch(cutoffEpoch: 1)
        }
        #expect(try await fixture.dataStore.getErasureValidatorCount(erasureRoot: root) == 6)
        if iterative {
            _ = try await cleanup.cleanupD3LEntries(retentionEpochs: 0)
        } else {
            _ = try await cleanup.cleanupD3LEntriesBeforeEpoch(cutoffEpoch: 1)
        }
        await #expect(throws: ErasureCodingStoreError.self) {
            try await fixture.dataStore.getErasureValidatorCount(erasureRoot: root)
        }
    }

    @Test
    func concurrentCodingCountsCannotOverwriteEachOther() async throws {
        let store = InMemoryDataStore()
        let root = data32(56)
        let accepted = await withTaskGroup(of: Int?.self, returning: Set<Int>.self) { group in
            for i in 0 ..< 32 {
                group.addTask {
                    let count = i.isMultiple(of: 2) ? 6 : 9
                    do {
                        try await store.setErasureValidatorCount(erasureRoot: root, count: count)
                        return count
                    } catch {
                        return nil
                    }
                }
            }
            var counts = Set<Int>()
            for await value in group {
                if let value {
                    counts.insert(value)
                }
            }
            return counts
        }
        #expect(accepted.count == 1)
        let stored = try await store.getErasureValidatorCount(erasureRoot: root)
        #expect(accepted == [stored])
    }

    @Test
    func storesAuditBundleAndReconstructsWhenFilesystemCopyIsMissing() async throws {
        let fixture = try makeFixture()
        defer { removeFixtureDirectory(fixture) }

        let bundle = Data((0 ..< 1000).map { UInt8(truncatingIfNeeded: $0 % 251) })
        let workPackageHash = data32(1)
        let segmentsRoot = data32(2)

        let erasureRoot = try await fixture.store.storeAuditBundle(
            bundle: bundle,
            workPackageHash: workPackageHash,
            segmentsRoot: segmentsRoot,
        )

        let entry = try #require(try await fixture.store.getAuditEntry(erasureRoot: erasureRoot))
        #expect(entry.workPackageHash == workPackageHash)
        #expect(entry.segmentsRoot == segmentsRoot)
        #expect(entry.bundleSize == bundle.count)
        #expect(try await fixture.dataStore.getErasureRoot(forSegmentRoot: segmentsRoot) == erasureRoot)
        #expect(try await fixture.store.getAuditBundle(erasureRoot: erasureRoot) == bundle)
        #expect(try await fixture.store.getLocalShardCount(erasureRoot: erasureRoot) == ProtocolConfigRef.dev.value.initialValidatorCount)
        #expect(try await fixture.store.canReconstructLocally(erasureRoot: erasureRoot))
        #expect(try await fixture.store.getReconstructionPotential(erasureRoot: erasureRoot) == 100.0)

        try await fixture.filesystemStore.deleteAuditBundle(erasureRoot: erasureRoot)

        #expect(try await fixture.store.getAuditBundle(erasureRoot: erasureRoot) == bundle)
    }

    @Test
    func storesExportedSegmentsAndRetrievesFilesystemBackedShards() async throws {
        let fixture = try makeFixture()
        defer { removeFixtureDirectory(fixture) }

        let segments = [
            Data4104(repeating: 1),
            Data4104(repeating: 2),
            Data4104(repeating: 3),
        ]
        let segmentsRoot = Merklization.binaryMerklize(segments.map(\.data))
        let workPackageHash = data32(3)

        let erasureRoot = try await fixture.store.storeExportedSegments(
            segments: segments,
            workPackageHash: workPackageHash,
            segmentsRoot: segmentsRoot,
        )

        let d3lEntry = try #require(try await fixture.store.getD3LEntry(erasureRoot: erasureRoot))
        #expect(d3lEntry.segmentsRoot == segmentsRoot)
        #expect(d3lEntry.segmentCount == UInt32(segments.count))
        #expect(try await fixture.store.getD3LErasureRoot(forSegmentsRoot: segmentsRoot) == erasureRoot)
        #expect(try await fixture.store.getPageCount(erasureRoot: erasureRoot) == 1)
        #expect(try await fixture.store.getPagedProofsMetadata(erasureRoot: erasureRoot) != nil)
        #expect(try await fixture.store.getLocalShardCount(erasureRoot: erasureRoot) == ProtocolConfigRef.dev.value.initialValidatorCount)
        #expect(try await fixture.store.canReconstructLocally(erasureRoot: erasureRoot))
        #expect(try await fixture.store.getReconstructionPotential(erasureRoot: erasureRoot) == 100.0)
        #expect(try await fixture.store.getMissingShardIndices(erasureRoot: erasureRoot).isEmpty)
        #expect(try await fixture.store.hasShard(erasureRoot: erasureRoot, shardIndex: 0))
        #expect(try await fixture.store.getShard(erasureRoot: erasureRoot, shardIndex: 0) != nil)

        let plan = try await fixture.store.getReconstructionPlan(erasureRoot: erasureRoot)
        #expect(plan.localShards == ProtocolConfigRef.dev.value.initialValidatorCount)
        #expect(plan.missingShards == 0)
        #expect(plan.canReconstructLocally)
        #expect(!plan.needsNetworkFetch)

        let localShards = try await fixture.store.getLocalShards(
            erasureRoot: erasureRoot,
            indices: [0, 1, 5],
        )
        #expect(localShards.map(\.index) == [0, 1, 5])

        let reconstructedData = try await fixture.store.reconstructFromLocalShards(
            erasureRoot: erasureRoot,
            originalLength: segments.count * 4104,
        )
        #expect(reconstructedData == segments.reduce(into: Data()) { $0.append($1.data) })

        let requested = try await fixture.store.getSegments(erasureRoot: erasureRoot, indices: [2, 0])
        #expect(requested == [segments[2], segments[0]])
        let partiallyInvalidRequest = try await fixture.store.getSegments(erasureRoot: erasureRoot, indices: [-1, 1, 99])
        #expect(partiallyInvalidRequest == [segments[1]])
        #expect(try await fixture.store.getAllSegments(erasureRoot: erasureRoot) == segments)
        #expect(try await fixture.store.getSegmentsByPage(erasureRoot: erasureRoot, pageIndex: 0) == segments)
        #expect(try await fixture.store.getSegmentsByPage(erasureRoot: erasureRoot, pageIndex: 1).isEmpty)
    }

    @Test
    func rejectsInvalidExportedSegmentRequests() async throws {
        let fixture = try makeFixture()
        defer { removeFixtureDirectory(fixture) }

        await expectStoreError(.noSegmentsToStore) {
            _ = try await fixture.store.storeExportedSegments(
                segments: [],
                workPackageHash: data32(4),
                segmentsRoot: data32(5),
            )
        }

        await expectStoreError(.segmentsRootMismatch) {
            _ = try await fixture.store.storeExportedSegments(
                segments: [Data4104(repeating: 6)],
                workPackageHash: data32(7),
                segmentsRoot: data32(8),
            )
        }
    }

    @Test(arguments: [6, 1023])
    func storageUsageAndCleanupOperateThroughFacade(validatorCount: Int) async throws {
        let fixture = try makeFixture()
        defer { removeFixtureDirectory(fixture) }

        let auditRoot = data32(10)
        let d3lRoot = data32(11)
        let oldTimestamp = Date().addingTimeInterval(-3600)
        try await fixture.dataStore.setErasureValidatorCount(erasureRoot: auditRoot, count: validatorCount)
        try await fixture.dataStore.setErasureValidatorCount(erasureRoot: d3lRoot, count: validatorCount)

        try await fixture.filesystemStore.storeAuditBundle(erasureRoot: auditRoot, data: Data(count: 1234))
        try await fixture.dataStore.setAuditEntry(
            workPackageHash: data32(12),
            erasureRoot: auditRoot,
            segmentsRoot: data32(13),
            bundleSize: 1234,
            timestamp: oldTimestamp,
        )
        try await fixture.dataStore.storeShards(
            shards: [(index: 0, data: Data(count: 684))],
            erasureRoot: auditRoot,
        )

        try await fixture.filesystemStore.storeD3LShard(
            erasureRoot: d3lRoot,
            shardIndex: 0,
            data: Data(count: 12),
        )
        try await fixture.dataStore.setD3LEntry(
            segmentsRoot: data32(14),
            erasureRoot: d3lRoot,
            segmentCount: 2,
            timestamp: oldTimestamp,
        )

        let usage = try await fixture.store.getStorageUsage()
        // Payload estimates assume complete shard sets, even with partial local data.
        let expectedAuditBytes = validatorCount == 6 ? 3706 : 5326
        let expectedD3LBytes = validatorCount == 6 ? 16416 : 24552
        let expectedTotalBytes = expectedAuditBytes + expectedD3LBytes
        #expect(usage.auditEntryCount == 1)
        #expect(usage.d3lEntryCount == 1)
        #expect(usage.totalBytes == expectedTotalBytes)
        #expect(usage.auditStoreBytes == expectedAuditBytes)
        #expect(usage.d3lStoreBytes == expectedD3LBytes)
        #expect(StoragePressure.from(usage: usage, maxBytes: usage.totalBytes + 1) == .emergency)

        let progress = try await fixture.store.incrementalCleanup(batchSize: 1, retentionEpochs: 1)
        #expect(progress.totalEntries == 1)
        #expect(progress.processedEntries == 1)
        #expect(progress.bytesReclaimed == expectedAuditBytes)
        #expect(progress.isComplete)
        #expect(try await fixture.store.getAuditEntry(erasureRoot: auditRoot) == nil)

        let d3lCleanup = try await fixture.store.cleanupD3LEntries(retentionEpochs: 1)
        #expect(d3lCleanup.entriesDeleted == 1)
        #expect(d3lCleanup.segmentsDeleted == 2)
        #expect(try await fixture.store.getD3LEntry(erasureRoot: d3lRoot) == nil)
        #expect(try await fixture.store.getLocalShardIndices(erasureRoot: d3lRoot).isEmpty)
    }

    @Test
    func reconstructionPlanReportsMissingAndAvailableShards() async throws {
        let fixture = try makeFixture()
        defer { removeFixtureDirectory(fixture) }

        let erasureRoot = data32(15)
        await #expect(throws: ErasureCodingStoreError.self) {
            try await fixture.store.getReconstructionPlan(erasureRoot: erasureRoot)
        }
        try await fixture.dataStore.setErasureValidatorCount(erasureRoot: erasureRoot, count: 1023)
        await #expect(throws: ErasureCodingStoreError.self) {
            try await fixture.dataStore.setErasureValidatorCount(erasureRoot: erasureRoot, count: 6)
        }
        for shardIndex in [UInt16(0), 2, 5] {
            try await fixture.dataStore.storeShard(
                shardData: Data([UInt8(shardIndex)]),
                erasureRoot: erasureRoot,
                shardIndex: shardIndex,
            )
        }

        let plan = try await fixture.store.getReconstructionPlan(erasureRoot: erasureRoot)
        #expect(plan.localShards == 3)
        #expect(plan.missingShards == 1020)
        #expect(!plan.canReconstructLocally)
        #expect(plan.needsNetworkFetch)
        #expect(plan.estimatedTimeToFetch == 102.0)
        #expect(plan.reconstructionPercentage == Double(3) / Double(342) * 100.0)

        let missing = try await fixture.store.getMissingShardIndices(erasureRoot: erasureRoot)
        #expect(missing.count == 1020)
        #expect(!missing.contains(0))
        #expect(!missing.contains(2))
        #expect(!missing.contains(5))
    }

    private enum ExpectedStoreError {
        case noSegmentsToStore
        case segmentsRootMismatch
    }

    private func expectStoreError(
        _ expected: ExpectedStoreError,
        operation: () async throws -> Void,
    ) async {
        do {
            try await operation()
            Issue.record("Expected \(expected)")
        } catch let error as ErasureCodingStoreError {
            switch (expected, error) {
            case (.noSegmentsToStore, .noSegmentsToStore):
                break
            case (.segmentsRootMismatch, .segmentsRootMismatch):
                break
            default:
                Issue.record("Expected \(expected), got \(error)")
            }
        } catch {
            Issue.record("Expected \(expected), got \(error)")
        }
    }
}
