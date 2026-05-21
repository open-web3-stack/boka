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
        #expect(try await fixture.store.getLocalShardCount(erasureRoot: erasureRoot) == 1023)
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
        #expect(try await fixture.store.getLocalShardCount(erasureRoot: erasureRoot) == 1023)
        #expect(try await fixture.store.canReconstructLocally(erasureRoot: erasureRoot))
        #expect(try await fixture.store.getReconstructionPotential(erasureRoot: erasureRoot) == 100.0)
        #expect(try await fixture.store.getMissingShardIndices(erasureRoot: erasureRoot).isEmpty)
        #expect(try await fixture.store.hasShard(erasureRoot: erasureRoot, shardIndex: 0))
        #expect(try await fixture.store.getShard(erasureRoot: erasureRoot, shardIndex: 0) != nil)

        let plan = try await fixture.store.getReconstructionPlan(erasureRoot: erasureRoot)
        #expect(plan.localShards == 1023)
        #expect(plan.missingShards == 0)
        #expect(plan.canReconstructLocally)
        #expect(!plan.needsNetworkFetch)

        let localShards = try await fixture.store.getLocalShards(
            erasureRoot: erasureRoot,
            indices: [0, 1, 1022],
        )
        #expect(localShards.map(\.index) == [0, 1, 1022])

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

    @Test
    func storageUsageAndCleanupOperateThroughFacade() async throws {
        let fixture = try makeFixture()
        defer { removeFixtureDirectory(fixture) }

        let auditRoot = data32(10)
        let d3lRoot = data32(11)
        let oldTimestamp = Date().addingTimeInterval(-3_600)

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
        let expectedTotalBytes = 1234 + 1023 * 684 + 2 * 4104
        #expect(usage.auditEntryCount == 1)
        #expect(usage.d3lEntryCount == 1)
        #expect(usage.totalBytes == expectedTotalBytes)
        #expect(StoragePressure.from(usage: usage, maxBytes: usage.totalBytes + 1) == .emergency)

        let progress = try await fixture.store.incrementalCleanup(batchSize: 1, retentionEpochs: 1)
        #expect(progress.totalEntries == 1)
        #expect(progress.processedEntries == 1)
        #expect(progress.bytesReclaimed == 1234)
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
