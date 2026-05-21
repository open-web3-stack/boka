@testable import Blockchain
import Foundation
import Testing
import Utils

struct InMemoryDataStoreBackendTests {
    @Test func deletesErasureRootMappingsAndAssociatedData() async throws {
        let backend = InMemoryDataStoreBackend()
        let segmentRoot = Data32.random()
        let d3lSegmentsRoot = Data32.random()
        let workPackageHash = Data32.random()
        let erasureRoot = Data32.random()
        let timestamp = Date(timeIntervalSince1970: 100)

        try await backend.set(erasureRoot: erasureRoot, forSegmentRoot: segmentRoot)
        try await backend.set(d3lErasureRoot: erasureRoot, forSegmentsRoot: d3lSegmentsRoot)
        try await backend.set(data: Data([1]), erasureRoot: erasureRoot, index: 0)
        try await backend.setTimestamp(erasureRoot: erasureRoot, timestamp: timestamp)
        try await backend.setPagedProofsMetadata(erasureRoot: erasureRoot, metadata: Data([2]))
        try await backend.setAuditEntry(
            workPackageHash: workPackageHash,
            erasureRoot: erasureRoot,
            segmentsRoot: segmentRoot,
            bundleSize: 1,
            timestamp: timestamp,
        )
        try await backend.setD3LEntry(
            segmentsRoot: d3lSegmentsRoot,
            erasureRoot: erasureRoot,
            segmentCount: 1,
            timestamp: timestamp,
        )

        try await backend.delete(erasureRoot: erasureRoot)

        #expect(try await backend.getErasureRoot(forSegmentRoot: segmentRoot) == nil)
        #expect(try await backend.getD3LErasureRoot(forSegmentsRoot: d3lSegmentsRoot) == nil)
        #expect(try await backend.get(erasureRoot: erasureRoot, index: 0) == nil)
        #expect(try await backend.getTimestamp(erasureRoot: erasureRoot) == nil)
        #expect(try await backend.getPagedProofsMetadata(erasureRoot: erasureRoot) == nil)
        #expect(try await backend.getAuditEntry(erasureRoot: erasureRoot) == nil)
        #expect(try await backend.getD3LEntry(erasureRoot: erasureRoot) == nil)
    }

    @Test func deletesWorkPackageMappingBySegmentRoot() async throws {
        let backend = InMemoryDataStoreBackend()
        let workPackageHash = Data32.random()
        let segmentRoot = Data32.random()

        try await backend.set(segmentRoot: segmentRoot, forWorkPackageHash: workPackageHash)
        #expect(try await backend.getSegmentRoot(forWorkPackageHash: workPackageHash) == segmentRoot)

        try await backend.delete(segmentRoot: segmentRoot)

        #expect(try await backend.getSegmentRoot(forWorkPackageHash: workPackageHash) == nil)
    }

    @Test func shardBatchOperationsPreserveRequestedOrderAndSkipMissingShards() async throws {
        let backend = InMemoryDataStoreBackend()
        let erasureRoot = Data32.random()

        try await backend.storeShards(shards: [
            (index: 2, data: Data([2])),
            (index: 0, data: Data([0])),
            (index: 1, data: Data([1])),
        ], erasureRoot: erasureRoot)

        let shards = try await backend.getShards(erasureRoot: erasureRoot, shardIndices: [1, 3, 0])

        #expect(shards.count == 2)
        #expect(shards[0].index == 1)
        #expect(shards[0].data == Data([1]))
        #expect(shards[1].index == 0)
        #expect(shards[1].data == Data([0]))
        #expect(try await backend.getShardCount(erasureRoot: erasureRoot) == 3)
        #expect(try await backend.getAvailableShardIndices(erasureRoot: erasureRoot) == [0, 1, 2])

        try await backend.deleteShards(erasureRoot: erasureRoot)

        #expect(try await backend.getShardCount(erasureRoot: erasureRoot) == 0)
        #expect(try await backend.getAvailableShardIndices(erasureRoot: erasureRoot).isEmpty)
    }

    @Test func cleanupAuditEntriesProcessesBatchesUntilProcessorStops() async throws {
        let backend = InMemoryDataStoreBackend()
        let oldDate = Date(timeIntervalSince1970: 10)
        let cutoff = Date(timeIntervalSince1970: 20)

        for bundleSize in 0 ..< 5 {
            try await backend.setAuditEntry(
                workPackageHash: Data32.random(),
                erasureRoot: Data32.random(),
                segmentsRoot: Data32.random(),
                bundleSize: bundleSize,
                timestamp: oldDate,
            )
        }

        let batchSizes = ThreadSafeContainer<[Int]>([])
        let processed = try await backend.cleanupAuditEntriesIteratively(before: cutoff, batchSize: 2) { entries in
            batchSizes.write { $0.append(entries.count) }
            return batchSizes.value.count < 2
        }

        #expect(processed == 4)
        #expect(batchSizes.value == [2, 2])
    }

    @Test func metadataRoundTrips() async throws {
        let backend = InMemoryDataStoreBackend()
        let key = Data([1, 2, 3])
        let value = Data([4, 5, 6])

        try await backend.setMetadata(key: key, value: value)

        #expect(try await backend.getMetadata(key: key) == value)
        #expect(try await backend.getMetadata(key: Data([9])) == nil)
    }
}
