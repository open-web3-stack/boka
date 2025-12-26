import Foundation

// DISABLED: This test creates a cyclic dependency between Blockchain and Database modules
// TODO: Restructure to avoid direct Database dependency in tests
#if DISABLED
    import RocksDBSwift
    import Testing
    import TracingUtils
    import Utils

    @testable import Blockchain

    struct PagedProofsTests {
        func makeDataStore() async throws -> ErasureCodingDataStore {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("pagedproofs_test_\(UUID().uuidString)")

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

        // MARK: - Paged-Proofs Metadata Tests

        @Test
        func generatePagedProofsMetadataForFullPage() async throws {
            let dataStore = try await makeDataStore()

            // Create exactly 64 segments (one full page)
            var segments: [Data4104] = []
            for i in 0 ..< 64 {
                var segmentData = Data(count: 4104)
                segmentData[0] = UInt8(truncatingIfNeeded: i)
                segments.append(Data4104(segmentData)!)
            }

            let workPackageHash = Data32.random()
            let segmentsRoot = Merklization.binaryMerklize(segments.map(\.data))

            // Store
            let erasureRoot = try await dataStore.storeExportedSegments(
                segments: segments,
                workPackageHash: workPackageHash,
                segmentsRoot: segmentsRoot
            )

            // Get Paged-Proofs metadata
            let metadata = try await dataStore.getPagedProofsMetadata(erasureRoot: erasureRoot)

            #expect(metadata != nil)
            #expect(metadata!.count > 0)

            // Get page count - should be 1
            let pageCount = try await dataStore.getPageCount(erasureRoot: erasureRoot)
            #expect(pageCount == 1)
        }

        @Test
        func generatePagedProofsMetadataForMultiplePages() async throws {
            let dataStore = try await makeDataStore()

            // Create 150 segments (3 pages: 64 + 64 + 22)
            var segments: [Data4104] = []
            for i in 0 ..< 150 {
                var segmentData = Data(count: 4104)
                segmentData[0] = UInt8(truncatingIfNeeded: i)
                segments.append(Data4104(segmentData)!)
            }

            let workPackageHash = Data32.random()
            let segmentsRoot = Merklization.binaryMerklize(segments.map(\.data))

            // Store
            let erasureRoot = try await dataStore.storeExportedSegments(
                segments: segments,
                workPackageHash: workPackageHash,
                segmentsRoot: segmentsRoot
            )

            // Get page count - should be 3
            let pageCount = try await dataStore.getPageCount(erasureRoot: erasureRoot)
            #expect(pageCount == 3)

            // Get Paged-Proofs metadata
            let metadata = try await dataStore.getPagedProofsMetadata(erasureRoot: erasureRoot)
            #expect(metadata != nil)
        }

        @Test
        func getSegmentsByPage() async throws {
            let dataStore = try await makeDataStore()

            // Create 100 segments
            var segments: [Data4104] = []
            for i in 0 ..< 100 {
                var segmentData = Data(count: 4104)
                segmentData[0] = UInt8(truncatingIfNeeded: i)
                segments.append(Data4104(segmentData)!)
            }

            let workPackageHash = Data32.random()
            let segmentsRoot = Merklization.binaryMerklize(segments.map(\.data))

            // Store
            let erasureRoot = try await dataStore.storeExportedSegments(
                segments: segments,
                workPackageHash: workPackageHash,
                segmentsRoot: segmentsRoot
            )

            // Get page 0 (segments 0-63)
            let page0 = try await dataStore.getSegmentsByPage(erasureRoot: erasureRoot, pageIndex: 0)
            #expect(page0.count == 64)
            #expect(page0[0][0] == 0)
            #expect(page0[63][0] == 63)

            // Get page 1 (segments 64-99)
            let page1 = try await dataStore.getSegmentsByPage(erasureRoot: erasureRoot, pageIndex: 1)
            #expect(page1.count == 36)
            #expect(page1[0][0] == 64)
            #expect(page1[35][0] == 99)

            // Get page 2 (out of bounds)
            let page2 = try await dataStore.getSegmentsByPage(erasureRoot: erasureRoot, pageIndex: 2)
            #expect(page2.isEmpty)
        }

        @Test
        func getPageCountForVariousSizes() async throws {
            let dataStore = try await makeDataStore()

            // Test 1: Exactly one page
            var segments: [Data4104] = []
            for _ in 0 ..< 64 {
                segments.append(Data4104())
            }

            let erasureRoot1 = try await dataStore.storeExportedSegments(
                segments: segments,
                workPackageHash: Data32.random(),
                segmentsRoot: Merklization.binaryMerklize(segments.map(\.data))
            )

            let count1 = try await dataStore.getPageCount(erasureRoot: erasureRoot1)
            #expect(count1 == 1)

            // Test 2: One page + 1 segment
            segments.removeAll()
            for _ in 0 ..< 65 {
                segments.append(Data4104())
            }

            let erasureRoot2 = try await dataStore.storeExportedSegments(
                segments: segments,
                workPackageHash: Data32.random(),
                segmentsRoot: Merklization.binaryMerklize(segments.map(\.data))
            )

            let count2 = try await dataStore.getPageCount(erasureRoot: erasureRoot2)
            #expect(count2 == 2)

            // Test 3: Exactly 10 pages
            segments.removeAll()
            for _ in 0 ..< 640 {
                segments.append(Data4104())
            }

            let erasureRoot3 = try await dataStore.storeExportedSegments(
                segments: segments,
                workPackageHash: Data32.random(),
                segmentsRoot: Merklization.binaryMerklize(segments.map(\.data))
            )

            let count3 = try await dataStore.getPageCount(erasureRoot: erasureRoot3)
            #expect(count3 == 10)
        }

        // MARK: - Segment Proof Verification Tests

        @Test
        func verifySegmentProof() async throws {
            let dataStore = try await makeDataStore()

            // Create segments
            var segments: [Data4104] = []
            for i in 0 ..< 10 {
                var segmentData = Data(count: 4104)
                segmentData[0] = UInt8(truncatingIfNeeded: i)
                segments.append(Data4104(segmentData)!)
            }

            let workPackageHash = Data32.random()
            let segmentsRoot = Merklization.binaryMerklize(segments.map(\.data))

            // Store
            let erasureRoot = try await dataStore.storeExportedSegments(
                segments: segments,
                workPackageHash: workPackageHash,
                segmentsRoot: segmentsRoot
            )

            // Get segment back
            let retrieved = try await dataStore.getSegments(erasureRoot: erasureRoot, indices: [5])
            #expect(retrieved.count == 1)

            // Generate a Merkle proof for the segment
            let proof = Merklization.trace(
                segments.map(\.data),
                index: 5,
                hasher: Blake2b256.self
            )

            var proofHashes: [Data32] = []
            for element in proof {
                switch element {
                case let .left(hash):
                    proofHashes.append(hash)
                case let .right(hash):
                    proofHashes.append(hash)
                }
            }

            // Verify the proof
            let isValid = try await dataStore.verifySegmentProof(
                segment: retrieved[0],
                pageIndex: 0,
                localIndex: 5,
                proof: proofHashes,
                segmentsRoot: segmentsRoot
            )

            #expect(isValid)
        }

        @Test
        func verifyInvalidSegmentProof() async throws {
            let dataStore = try await makeDataStore()

            // Create segments
            var segments: [Data4104] = []
            for i in 0 ..< 10 {
                var segmentData = Data(count: 4104)
                segmentData[0] = UInt8(truncatingIfNeeded: i)
                segments.append(Data4104(segmentData)!)
            }

            let workPackageHash = Data32.random()
            let segmentsRoot = Merklization.binaryMerklize(segments.map(\.data))

            // Store
            let erasureRoot = try await dataStore.storeExportedSegments(
                segments: segments,
                workPackageHash: workPackageHash,
                segmentsRoot: segmentsRoot
            )

            // Get segment back
            let retrieved = try await dataStore.getSegments(erasureRoot: erasureRoot, indices: [5])
            #expect(retrieved.count == 1)

            // Create fake proof
            let fakeProof = Array(repeating: Data32.random(), count: 6)

            // Verify the fake proof should fail
            let isValid = try await dataStore.verifySegmentProof(
                segment: retrieved[0],
                pageIndex: 0,
                localIndex: 5,
                proof: fakeProof,
                segmentsRoot: segmentsRoot
            )

            #expect(!isValid)
        }

        // MARK: - Large-Scale Tests

        @Test
        func storeLargeSegmentSet() async throws {
            let dataStore = try await makeDataStore()

            // Create near-maximum segment set (3000 segments, just under 3072 limit)
            var segments: [Data4104] = []
            for i in 0 ..< 3000 {
                var segmentData = Data(count: 4104)
                segmentData[0] = UInt8(truncatingIfNeeded: i % 256)
                segments.append(Data4104(segmentData)!)
            }

            let workPackageHash = Data32.random()
            let segmentsRoot = Merklization.binaryMerklize(segments.map(\.data))

            // Store
            let erasureRoot = try await dataStore.storeExportedSegments(
                segments: segments,
                workPackageHash: workPackageHash,
                segmentsRoot: segmentsRoot
            )

            // Get page count
            let pageCount = try await dataStore.getPageCount(erasureRoot: erasureRoot)
            #expect(pageCount == 47) // (3000 + 63) / 64 = 47

            // Retrieve first page
            let firstPage = try await dataStore.getSegmentsByPage(erasureRoot: erasureRoot, pageIndex: 0)
            #expect(firstPage.count == 64)

            // Retrieve last page (partial)
            let lastPage = try await dataStore.getSegmentsByPage(erasureRoot: erasureRoot, pageIndex: 46)
            #expect(lastPage.count == 3000 % 64)
        }

        // MARK: - Cleanup Tests

        @Test
        func cleanupD3LEntries() async throws {
            let dataStore = try await makeDataStore()

            // Create and store segments
            var segments: [Data4104] = []
            for _ in 0 ..< 100 {
                segments.append(Data4104())
            }

            let workPackageHash = Data32.random()
            let segmentsRoot = Merklization.binaryMerklize(segments.map(\.data))

            let erasureRoot = try await dataStore.storeExportedSegments(
                segments: segments,
                workPackageHash: workPackageHash,
                segmentsRoot: segmentsRoot
            )

            // Manually set old timestamp
            try await dataStore.rocksdbStore.setTimestamp(
                erasureRoot: erasureRoot,
                timestamp: Date().addingTimeInterval(-100_000)
            )

            // Cleanup
            let result = try await dataStore.cleanupD3LEntries(retentionEpochs: 0)

            #expect(result.entriesDeleted == 1)
            #expect(result.segmentsDeleted == 100)
        }

        // MARK: - Metadata Tests

        @Test
        func getPagedProofsMetadata() async throws {
            let dataStore = try await makeDataStore()

            // Create segments
            var segments: [Data4104] = []
            for _ in 0 ..< 128 {
                segments.append(Data4104())
            }

            let workPackageHash = Data32.random()
            let segmentsRoot = Merklization.binaryMerklize(segments.map(\.data))

            // Store
            let erasureRoot = try await dataStore.storeExportedSegments(
                segments: segments,
                workPackageHash: workPackageHash,
                segmentsRoot: segmentsRoot
            )

            // Get metadata
            let metadata = try await dataStore.getPagedProofsMetadata(erasureRoot: erasureRoot)

            #expect(metadata != nil)
            #expect(metadata!.count > 0)
        }

        @Test
        func getMissingMetadata() async throws {
            let dataStore = try await makeDataStore()

            // Try to get metadata for non-existent erasure root
            let metadata = try await dataStore.getPagedProofsMetadata(erasureRoot: Data32.random())

            #expect(metadata == nil)
        }
    }
#endif
