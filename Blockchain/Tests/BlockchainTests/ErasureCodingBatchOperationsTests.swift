@testable import Blockchain
import Foundation
import Testing
import Utils

@Suite(.serialized)
struct ErasureCodingBatchOperationsTests {
    private struct Fixture {
        let store: ErasureCodingDataStore
        let dataStore: InMemoryDataStore
        let tempDir: URL
    }

    private func makeFixture() throws -> Fixture {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("erasure_coding_batch_test_\(UUID().uuidString)")
        let dataStore = InMemoryDataStore()
        let filesystemStore = try FilesystemDataStore(dataPath: tempDir)
        let store = ErasureCodingDataStore(
            dataStore: dataStore,
            filesystemStore: filesystemStore,
            config: .dev,
        )
        return Fixture(store: store, dataStore: dataStore, tempDir: tempDir)
    }

    private func removeFixtureDirectory(_ fixture: Fixture) {
        try? FileManager.default.removeItem(at: fixture.tempDir)
    }

    @Test
    func batchGetsSegmentsForAvailableRootsAndSkipsMissingRoots() async throws {
        let fixture = try makeFixture()
        defer { removeFixtureDirectory(fixture) }

        let segments = [Data4104(repeating: 7), Data4104(repeating: 8)]
        let segmentsRoot = Merklization.binaryMerklize(segments.map(\.data))
        let erasureRoot = try await fixture.store.storeExportedSegments(
            segments: segments,
            workPackageHash: data32(20),
            segmentsRoot: segmentsRoot,
        )
        let missingRoot = data32(21)

        let results = try await fixture.store.batchGetSegments(requests: [
            BatchSegmentRequest(erasureRoot: erasureRoot, indices: [1, 0]),
            BatchSegmentRequest(erasureRoot: missingRoot, indices: [0]),
        ])

        #expect(results[erasureRoot] == [segments[1], segments[0]])
        #expect(results[missingRoot] == nil)
    }

    @Test
    func batchReconstructsAuditBundlesAndFilesystemBackedSegments() async throws {
        let fixture = try makeFixture()
        defer { removeFixtureDirectory(fixture) }

        let bundle = Data((0 ..< 1536).map { UInt8(truncatingIfNeeded: $0) })
        let auditRoot = try await fixture.store.storeAuditBundle(
            bundle: bundle,
            workPackageHash: data32(22),
            segmentsRoot: data32(23),
        )

        let segments = [Data4104(repeating: 9), Data4104(repeating: 10)]
        let expectedSegmentsData = segments.reduce(into: Data()) { data, segment in
            data.append(segment.data)
        }
        let segmentsRoot = Merklization.binaryMerklize(segments.map(\.data))
        let d3lRoot = try await fixture.store.storeExportedSegments(
            segments: segments,
            workPackageHash: data32(24),
            segmentsRoot: segmentsRoot,
        )

        let results = try await fixture.store.batchReconstruct(
            erasureRoots: [auditRoot, d3lRoot],
            originalLengths: [
                auditRoot: bundle.count,
                d3lRoot: expectedSegmentsData.count,
            ],
        )

        #expect(results[auditRoot] == bundle)
        #expect(results[d3lRoot] == expectedSegmentsData)
    }

    @Test
    func batchReconstructRejectsMissingOriginalLength() async throws {
        let fixture = try makeFixture()
        defer { removeFixtureDirectory(fixture) }

        let erasureRoot = try await fixture.store.storeAuditBundle(
            bundle: Data(repeating: 11, count: 512),
            workPackageHash: data32(25),
            segmentsRoot: data32(26),
        )

        await expectStoreError(.missingOriginalLength(erasureRoot)) {
            _ = try await fixture.store.batchReconstruct(
                erasureRoots: [erasureRoot],
                originalLengths: [:],
            )
        }
    }

    @Test
    func batchReconstructRejectsInsufficientLocalShardsWithoutFallback() async throws {
        let fixture = try makeFixture()
        defer { removeFixtureDirectory(fixture) }

        let erasureRoot = data32(27)
        try await fixture.dataStore.storeShard(
            shardData: Data(repeating: 12, count: 684),
            erasureRoot: erasureRoot,
            shardIndex: 0,
        )

        await expectStoreError(.insufficientShards(available: 1, required: 342)) {
            _ = try await fixture.store.batchReconstruct(
                erasureRoots: [erasureRoot],
                originalLengths: [erasureRoot: 684],
            )
        }
    }

    private enum ExpectedStoreError {
        case insufficientShards(available: Int, required: Int)
        case missingOriginalLength(Data32)
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
            case let (.insufficientShards(expectedAvailable, expectedRequired), .insufficientShards(actualAvailable, actualRequired)):
                #expect(actualAvailable == expectedAvailable)
                #expect(actualRequired == expectedRequired)
            case let (.missingOriginalLength(expectedRoot), .missingOriginalLength(actualRoot)):
                #expect(actualRoot == expectedRoot)
            default:
                Issue.record("Expected \(expected), got \(error)")
            }
        } catch {
            Issue.record("Expected \(expected), got \(error)")
        }
    }
}
