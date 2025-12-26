import Foundation
#if DISABLED
    // Disabled: Needs refactoring for actor-isolated APIs and async/await changes

    import Testing
    import TracingUtils
    import Utils

    @testable import Blockchain

    /// Tests for local shard retrieval, caching, and reconstruction (Milestone 5)
    struct ShardRetrievalTests {
        func makeDataStore() async throws -> ErasureCodingDataStore {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("shard_retrieval_test_\(UUID().uuidString)")

            let db = try RocksDB<StoreId>(path: tempDir, columnFamilies: StoreId.allCases)

            for cf in StoreId.allCases.dropFirst() {
                try db.createColumnFamily(named: cf)
            }

            let rocksdbStore = InMemoryStore(db, config: .dev)
            let filesystemStore = await FilesystemDataStore(dataPath: tempDir)

            return ErasureCodingDataStore(
                rocksdbStore: rocksdbStore,
                filesystemStore: filesystemStore,
                config: .dev
            )
        }

        // MARK: - Local Shard Retrieval Tests

        @Test
        func getLocalShardCount() async throws {
            let dataStore = try await makeDataStore()

            // Store test bundle
            let bundleData = Data(count: 10000)
            let erasureRoot = try await dataStore.storeAuditBundle(
                bundle: bundleData,
                workPackageHash: Data32.random(),
                segmentsRoot: Data32.random()
            )

            // Should have all 1023 shards
            let shardCount = try await dataStore.getLocalShardCount(erasureRoot: erasureRoot)
            #expect(shardCount == 1023)
        }

        @Test
        func getLocalShardIndices() async throws {
            let dataStore = try await makeDataStore()

            // Store test bundle
            let bundleData = Data(count: 10000)
            let erasureRoot = try await dataStore.storeAuditBundle(
                bundle: bundleData,
                workPackageHash: Data32.random(),
                segmentsRoot: Data32.random()
            )

            // Should have all indices 0-1022
            let indices = try await dataStore.getLocalShardIndices(erasureRoot: erasureRoot)
            #expect(indices.count == 1023)
            #expect(indices.contains(0))
            #expect(indices.contains(511))
            #expect(indices.contains(1022))
        }

        @Test
        func getLocalShards() async throws {
            let dataStore = try await makeDataStore()

            // Store test bundle
            let bundleData = Data(count: 10000)
            let erasureRoot = try await dataStore.storeAuditBundle(
                bundle: bundleData,
                workPackageHash: Data32.random(),
                segmentsRoot: Data32.random()
            )

            // Get specific shards
            let requestedIndices: [UInt16] = [0, 100, 500, 1022]
            let shards = try await dataStore.getLocalShards(
                erasureRoot: erasureRoot,
                indices: requestedIndices
            )

            #expect(shards.count == requestedIndices.count)
            for (index, _) in shards {
                #expect(requestedIndices.contains(index))
            }
        }

        @Test
        func getLocalShardsForNonExistentErasureRoot() async throws {
            let dataStore = try await makeDataStore()

            let randomRoot = Data32.random()
            let shards = try await dataStore.getLocalShards(
                erasureRoot: randomRoot,
                indices: [0, 1, 2]
            )

            #expect(shards.isEmpty)
        }

        // MARK: - Cache Tests

        @Test
        func segmentCacheHit() async throws {
            let dataStore = try await makeDataStore()

            // Store segments
            var segments: [Data4104] = []
            for i in 0 ..< 10 {
                var segmentData = Data(count: 4104)
                segmentData[0] = UInt8(truncatingIfNeeded: i)
                segments.append(Data4104(segmentData)!)
            }

            let workPackageHash = Data32.random()
            let segmentsRoot = Merklization.binaryMerklize(segments.map(\.data))

            let erasureRoot = try await dataStore.storeExportedSegments(
                segments: segments,
                workPackageHash: workPackageHash,
                segmentsRoot: segmentsRoot
            )

            // First access - cache miss
            let retrieved1 = try await dataStore.getSegmentsWithCache(
                erasureRoot: erasureRoot,
                indices: [0, 1, 2]
            )
            #expect(retrieved1.count == 3)

            // Second access - should hit cache
            let retrieved2 = try await dataStore.getSegmentsWithCache(
                erasureRoot: erasureRoot,
                indices: [0, 1, 2]
            )
            #expect(retrieved2.count == 3)

            // Check cache statistics
            let stats = dataStore.getCacheStatistics()
            #expect(stats.hits > 0)
            #expect(stats.misses > 0)
        }

        @Test
        func cacheInvalidation() async throws {
            let dataStore = try await makeDataStore()

            // Store segments
            var segments: [Data4104] = []
            for _ in 0 ..< 5 {
                segments.append(Data4104())
            }

            let workPackageHash = Data32.random()
            let segmentsRoot = Merklization.binaryMerklize(segments.map(\.data))

            let erasureRoot = try await dataStore.storeExportedSegments(
                segments: segments,
                workPackageHash: workPackageHash,
                segmentsRoot: segmentsRoot
            )

            // Access segments to populate cache
            _ = try await dataStore.getSegmentsWithCache(erasureRoot: erasureRoot, indices: [0, 1, 2])

            // Clear cache for this erasure root
            dataStore.clearCache(erasureRoot: erasureRoot)

            // Access again - should be cache miss
            let statsBefore = dataStore.getCacheStatistics()
            _ = try await dataStore.getSegmentsWithCache(erasureRoot: erasureRoot, indices: [0, 1, 2])
            let statsAfter = dataStore.getCacheStatistics()

            #expect(statsAfter.misses > statsBefore.misses)
        }

        @Test
        func clearAllCache() async throws {
            let dataStore = try await makeDataStore()

            // Store multiple segment sets
            for i in 0 ..< 3 {
                var segments: [Data4104] = []
                for _ in 0 ..< 5 {
                    segments.append(Data4104())
                }

                let workPackageHash = Data32.random()
                let segmentsRoot = Merklization.binaryMerklize(segments.map(\.data))

                _ = try await dataStore.storeExportedSegments(
                    segments: segments,
                    workPackageHash: workPackageHash,
                    segmentsRoot: segmentsRoot
                )
            }

            // Access segments to populate cache
            let statsBefore = dataStore.getCacheStatistics()
            #expect(statsBefore.size > 0)

            // Clear all cache
            dataStore.clearAllCache()

            let statsAfter = dataStore.getCacheStatistics()
            #expect(statsAfter.size == 0)
        }

        // MARK: - Reconstruction Tests

        @Test
        func canReconstructLocally() async throws {
            let dataStore = try await makeDataStore()

            // Store bundle
            let bundleData = Data(count: 10000)
            let erasureRoot = try await dataStore.storeAuditBundle(
                bundle: bundleData,
                workPackageHash: Data32.random(),
                segmentsRoot: Data32.random()
            )

            // Should be able to reconstruct with all 1023 shards
            let canReconstruct = try await dataStore.canReconstructLocally(erasureRoot: erasureRoot)
            #expect(canReconstruct)
        }

        @Test
        func cannotReconstructWithInsufficientShards() async throws {
            let dataStore = try await makeDataStore()

            // Create bundle and erasure code it
            let bundleData = Data(count: 10000)
            let erasureRoot = try await dataStore.storeAuditBundle(
                bundle: bundleData,
                workPackageHash: Data32.random(),
                segmentsRoot: Data32.random()
            )

            // Delete some shards to simulate loss
            for i in 0 ..< 700 {
                try await dataStore.dataStoreForTesting.deleteShard(
                    erasureRoot: erasureRoot,
                    shardIndex: UInt16(i)
                )
            }

            // Should not be able to reconstruct with only 323 shards
            let canReconstruct = try await dataStore.canReconstructLocally(erasureRoot: erasureRoot)
            #expect(!canReconstruct)
        }

        @Test
        func getReconstructionPotential() async throws {
            let dataStore = try await makeDataStore()

            // Store bundle
            let bundleData = Data(count: 10000)
            let erasureRoot = try await dataStore.storeAuditBundle(
                bundle: bundleData,
                workPackageHash: Data32.random(),
                segmentsRoot: Data32.random()
            )

            // With all shards, should be 100%
            let potential = try await dataStore.getReconstructionPotential(erasureRoot: erasureRoot)
            #expect(potential == 100.0)
        }

        @Test
        func getMissingShardIndices() async throws {
            let dataStore = try await makeDataStore()

            // Store bundle
            let bundleData = Data(count: 10000)
            let erasureRoot = try await dataStore.storeAuditBundle(
                bundle: bundleData,
                workPackageHash: Data32.random(),
                segmentsRoot: Data32.random()
            )

            // Delete some shards
            for i in 0 ..< 10 {
                try await dataStore.dataStoreForTesting.deleteShard(
                    erasureRoot: erasureRoot,
                    shardIndex: UInt16(i)
                )
            }

            // Should report missing indices
            let missing = try await dataStore.getMissingShardIndices(erasureRoot: erasureRoot)
            #expect(missing.count == 10)
            #expect(missing.contains(0))
            #expect(missing.contains(9))
        }

        @Test
        func getReconstructionPlan() async throws {
            let dataStore = try await makeDataStore()

            // Store bundle
            let bundleData = Data(count: 10000)
            let erasureRoot = try await dataStore.storeAuditBundle(
                bundle: bundleData,
                workPackageHash: Data32.random(),
                segmentsRoot: Data32.random()
            )

            let plan = try await dataStore.getReconstructionPlan(erasureRoot: erasureRoot)

            #expect(plan.localShards == 1023)
            #expect(plan.missingShards == 0)
            #expect(plan.canReconstructLocally)
            #expect(plan.reconstructionPercentage >= 100.0)
            #expect(!plan.needsNetworkFetch)
        }

        @Test
        func reconstructFromLocalShards() async throws {
            let dataStore = try await makeDataStore()

            // Create test data
            let originalData: [UInt8] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
            var testData = Data(count: 10000)
            for (index, byte) in originalData.enumerated() {
                testData[index] = byte
            }

            // Store bundle
            let erasureRoot = try await dataStore.storeAuditBundle(
                bundle: testData,
                workPackageHash: Data32.random(),
                segmentsRoot: Data32.random()
            )

            // Reconstruct
            let reconstructed = try await dataStore.reconstructFromLocalShards(
                erasureRoot: erasureRoot,
                originalLength: testData.count
            )

            #expect(reconstructed.count == testData.count)

            // Verify data integrity
            for (index, byte) in originalData.enumerated() {
                #expect(reconstructed[index] == byte)
            }
        }

        @Test
        func reconstructWithInsufficientShardsThrowsError() async throws {
            let dataStore = try await makeDataStore()

            // Store bundle
            let bundleData = Data(count: 10000)
            let erasureRoot = try await dataStore.storeAuditBundle(
                bundle: bundleData,
                workPackageHash: Data32.random(),
                segmentsRoot: Data32.random()
            )

            // Delete most shards
            for i in 0 ..< 700 {
                try await dataStore.dataStoreForTesting.deleteShard(
                    erasureRoot: erasureRoot,
                    shardIndex: UInt16(i)
                )
            }

            // Should throw error
            #expect(throws: DataAvailabilityError.self) {
                try await dataStore.reconstructFromLocalShards(
                    erasureRoot: erasureRoot,
                    originalLength: bundleData.count
                )
            }
        }

        // MARK: - Batch Operations Tests

        @Test
        func batchGetSegments() async throws {
            let dataStore = try await makeDataStore()

            // Store multiple segment sets
            var erasureRoots: [Data32] = []

            for setNum in 0 ..< 3 {
                var segments: [Data4104] = []
                for i in 0 ..< 10 {
                    var segmentData = Data(count: 4104)
                    segmentData[0] = UInt8(truncatingIfNeeded: setNum * 10 + i)
                    segments.append(Data4104(segmentData)!)
                }

                let workPackageHash = Data32.random()
                let segmentsRoot = Merklization.binaryMerklize(segments.map(\.data))

                let erasureRoot = try await dataStore.storeExportedSegments(
                    segments: segments,
                    workPackageHash: workPackageHash,
                    segmentsRoot: segmentsRoot
                )

                erasureRoots.append(erasureRoot)
            }

            // Batch get
            let requests = erasureRoots.map { erasureRoot in
                BatchSegmentRequest(erasureRoot: erasureRoot, indices: [0, 1, 2])
            }

            let results = try await dataStore.batchGetSegments(requests: requests)

            #expect(results.count == 3)
            for erasureRoot in erasureRoots {
                #expect(results[erasureRoot]?.count == 3)
            }
        }

        @Test
        func batchReconstruct() async throws {
            let dataStore = try await makeDataStore()

            // Store multiple bundles
            var erasureRoots: [Data32] = []
            var originalLengths: [Data32: Int] = [:]

            for i in 0 ..< 3 {
                var testData = Data(count: 10000)
                testData[0] = UInt8(truncatingIfNeeded: i)

                let erasureRoot = try await dataStore.storeAuditBundle(
                    bundle: testData,
                    workPackageHash: Data32.random(),
                    segmentsRoot: Data32.random()
                )

                erasureRoots.append(erasureRoot)
                originalLengths[erasureRoot] = testData.count
            }

            // Batch reconstruct
            let results = try await dataStore.batchReconstruct(
                erasureRoots: erasureRoots,
                originalLengths: originalLengths
            )

            #expect(results.count == 3)

            // Verify reconstructed data
            for (i, erasureRoot) in erasureRoots.enumerated() {
                let data = results[erasureRoot]
                #expect(data != nil)
                #expect(data?[0] == UInt8(i))
            }
        }

        @Test
        func batchReconstructWithPartialFailure() async throws {
            let dataStore = try await makeDataStore()

            // Store bundles
            var erasureRoots: [Data32] = []
            var originalLengths: [Data32: Int] = [:]

            for i in 0 ..< 3 {
                let testData = Data(count: 10000)

                let erasureRoot = try await dataStore.storeAuditBundle(
                    bundle: testData,
                    workPackageHash: Data32.random(),
                    segmentsRoot: Data32.random()
                )

                erasureRoots.append(erasureRoot)
                originalLengths[erasureRoot] = testData.count
            }

            // Delete shards from first bundle to make it fail
            for i in 0 ..< 700 {
                try await dataStore.dataStoreForTesting.deleteShard(
                    erasureRoot: erasureRoots[0],
                    shardIndex: UInt16(i)
                )
            }

            // Batch reconstruct - should continue despite one failure
            let results = try await dataStore.batchReconstruct(
                erasureRoots: erasureRoots,
                originalLengths: originalLengths
            )

            // Should have 2 successful reconstructions
            #expect(results.count == 2)
            #expect(results[erasureRoots[0]] == nil)
            #expect(results[erasureRoots[1]] != nil)
            #expect(results[erasureRoots[2]] != nil)
        }
    }
#endif
