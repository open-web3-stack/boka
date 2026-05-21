@testable import Blockchain
import Foundation
import Testing
import Utils

struct DataStoreTests {
    private func makeStore() -> (backend: InMemoryDataStoreBackend, store: DataStore) {
        let backend = InMemoryDataStoreBackend()
        return (backend, DataStore(backend, backend))
    }

    @Test func fetchSegmentByDirectSegmentRoot() async throws {
        let (backend, store) = makeStore()
        let segmentRoot = Data32.random()
        let erasureRoot = Data32.random()
        let segment = Data4104(repeating: 9)

        try await backend.set(erasureRoot: erasureRoot, forSegmentRoot: segmentRoot)
        try await store.set(data: segment, erasureRoot: erasureRoot, index: 3)

        let result = try await store.fetchSegment(
            segments: [WorkItem.ImportedDataSegment(root: .segmentRoot(segmentRoot), index: 3)],
            segmentsRootMappings: nil,
        )

        #expect(result == [segment])
    }

    @Test func fetchSegmentByWorkPackageMapping() async throws {
        let (backend, store) = makeStore()
        let workPackageHash = Data32.random()
        let segmentRoot = Data32.random()
        let erasureRoot = Data32.random()
        let segment = Data4104(repeating: 4)

        try await backend.set(erasureRoot: erasureRoot, forSegmentRoot: segmentRoot)
        try await store.set(data: segment, erasureRoot: erasureRoot, index: 1)

        let result = try await store.fetchSegment(
            segments: [WorkItem.ImportedDataSegment(root: .workPackageHash(workPackageHash), index: 1)],
            segmentsRootMappings: [SegmentsRootMapping(workPackageHash: workPackageHash, segmentsRoot: segmentRoot)],
        )

        #expect(result == [segment])
    }

    @Test func fetchSegmentByStoredWorkPackageMapping() async throws {
        let (backend, store) = makeStore()
        let workPackageHash = Data32.random()
        let segmentRoot = Data32.random()
        let erasureRoot = Data32.random()
        let segment = Data4104(repeating: 5)

        try await store.setSegmentRoot(segmentRoot: segmentRoot, forWorkPackageHash: workPackageHash)
        try await backend.set(erasureRoot: erasureRoot, forSegmentRoot: segmentRoot)
        try await store.set(data: segment, erasureRoot: erasureRoot, index: 2)

        let result = try await store.fetchSegment(
            segments: [WorkItem.ImportedDataSegment(root: .workPackageHash(workPackageHash), index: 2)],
            segmentsRootMappings: nil,
        )

        #expect(result == [segment])
    }

    @Test func fetchSegmentThrowsForMissingWorkPackageMapping() async throws {
        let (_, store) = makeStore()
        let workPackageHash = Data32.random()

        await #expect(throws: DataStoreError.self) {
            _ = try await store.fetchSegment(
                segments: [WorkItem.ImportedDataSegment(root: .workPackageHash(workPackageHash), index: 0)],
                segmentsRootMappings: [],
            )
        }
    }

    @Test func fetchSegmentThrowsForMissingErasureRoot() async throws {
        let (_, store) = makeStore()
        let segmentRoot = Data32.random()

        await #expect(throws: DataStoreError.self) {
            _ = try await store.fetchSegment(
                segments: [WorkItem.ImportedDataSegment(root: .segmentRoot(segmentRoot), index: 0)],
                segmentsRootMappings: nil,
            )
        }
    }

    @Test func fetchSegmentThrowsForInvalidStoredLength() async throws {
        let (backend, store) = makeStore()
        let segmentRoot = Data32.random()
        let erasureRoot = Data32.random()

        try await backend.set(erasureRoot: erasureRoot, forSegmentRoot: segmentRoot)
        try await backend.set(data: Data([1, 2, 3]), erasureRoot: erasureRoot, index: 0)

        await #expect(throws: DataStoreError.self) {
            _ = try await store.fetchSegment(
                segments: [WorkItem.ImportedDataSegment(root: .segmentRoot(segmentRoot), index: 0)],
                segmentsRootMappings: nil,
            )
        }
    }

    @Test func fetchSegmentThrowsWhenNetworkFetchWouldBeRequired() async throws {
        let (backend, store) = makeStore()
        let segmentRoot = Data32.random()
        let erasureRoot = Data32.random()

        try await backend.set(erasureRoot: erasureRoot, forSegmentRoot: segmentRoot)

        await #expect(throws: DataStoreError.self) {
            _ = try await store.fetchSegment(
                segments: [WorkItem.ImportedDataSegment(root: .segmentRoot(segmentRoot), index: 0)],
                segmentsRootMappings: nil,
            )
        }
    }

    @Test func metadataRoundTripsThroughBackend() async throws {
        let (_, store) = makeStore()
        let erasureRoot = Data32.random()
        let timestamp = Date(timeIntervalSince1970: 1_735_732_900)
        let metadata = Data([1, 2, 3])

        try await store.setTimestamp(erasureRoot: erasureRoot, timestamp: timestamp)
        try await store.setPagedProofsMetadata(erasureRoot: erasureRoot, metadata: metadata)

        #expect(try await store.getTimestamp(erasureRoot: erasureRoot) == timestamp)
        #expect(try await store.getPagedProofsMetadata(erasureRoot: erasureRoot) == metadata)
    }
}
