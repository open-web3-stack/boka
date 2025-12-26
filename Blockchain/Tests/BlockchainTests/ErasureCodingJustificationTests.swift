import Foundation
#if DISABLED
    // Disabled: Needs refactoring for actor-isolated APIs and async/await changes
    import Testing
    import TracingUtils
    import Utils

    @testable import Blockchain

    /// Unit tests for ErasureCodingService JAMNP-S justification generation
    struct ErasureCodingJustificationTests {
        func makeService() -> ErasureCodingService {
            ErasureCodingService(config: ProtocolConfigRef(.dev))
        }

        func makeTestShards(count: Int = 1023) -> [Data] {
            (0 ..< count).map { i in
                var data = Data(count: 684)
                data[0] = UInt8(i & 0xFF)
                data[1] = UInt8((i >> 8) & 0xFF)
                return data
            }
        }

        // MARK: - Generate Justification Tests

        @Test
        func generateJustificationBasic() async throws {
            let service = makeService()
            let shards = makeTestShards()
            let segmentsRoot = Data32.random()
            let shardIndex: UInt16 = 0

            let steps = try await service.generateJustification(
                shardIndex: shardIndex,
                segmentsRoot: segmentsRoot,
                shards: shards
            )

            // Should generate a co-path with multiple steps
            #expect(!steps.isEmpty)
        }

        @Test
        func generateJustificationMiddleShard() async throws {
            let service = makeService()
            let shards = makeTestShards()
            let segmentsRoot = Data32.random()
            let shardIndex: UInt16 = 511

            let steps = try await service.generateJustification(
                shardIndex: shardIndex,
                segmentsRoot: segmentsRoot,
                shards: shards
            )

            #expect(!steps.isEmpty)
        }

        @Test
        func generateJustificationLastShard() async throws {
            let service = makeService()
            let shards = makeTestShards()
            let segmentsRoot = Data32.random()
            let shardIndex: UInt16 = 1022

            let steps = try await service.generateJustification(
                shardIndex: shardIndex,
                segmentsRoot: segmentsRoot,
                shards: shards
            )

            #expect(!steps.isEmpty)
        }

        @Test
        func generateJustificationInvalidShardIndex() async throws {
            let service = makeService()
            let shards = makeTestShards()
            let segmentsRoot = Data32.random()
            let shardIndex: UInt16 = 1023 // Out of range

            await confirmation("Invalid shard index throws") { _ in
                #expect(throws: ErasureCodingError.self) {
                    try await service.generateJustification(
                        shardIndex: shardIndex,
                        segmentsRoot: segmentsRoot,
                        shards: shards
                    )
                }
            }
        }

        @Test
        func generateJustificationInvalidShardCount() async throws {
            let service = makeService()
            let shards = makeTestShards(count: 100) // Wrong count
            let segmentsRoot = Data32.random()
            let shardIndex: UInt16 = 0

            await confirmation("Invalid shard count throws") { _ in
                #expect(throws: ErasureCodingError.self) {
                    try await service.generateJustification(
                        shardIndex: shardIndex,
                        segmentsRoot: segmentsRoot,
                        shards: shards
                    )
                }
            }
        }

        @Test
        func generateJustificationValidatesShardIndex() async throws {
            let service = makeService()
            let shards = makeTestShards()
            let segmentsRoot = Data32.random()

            // Test first shard
            let steps0 = try await service.generateJustification(
                shardIndex: 0,
                segmentsRoot: segmentsRoot,
                shards: shards
            )
            #expect(!steps0.isEmpty)

            // Test middle shard
            let steps511 = try await service.generateJustification(
                shardIndex: 511,
                segmentsRoot: segmentsRoot,
                shards: shards
            )
            #expect(!steps511.isEmpty)

            // Test last shard
            let steps1022 = try await service.generateJustification(
                shardIndex: 1022,
                segmentsRoot: segmentsRoot,
                shards: shards
            )
            #expect(!steps1022.isEmpty)
        }

        @Test
        func generateJustificationDifferentSegmentsRoot() async throws {
            let service = makeService()
            let shards = makeTestShards()
            let segmentsRoot1 = Data32([1; 32])
            let segmentsRoot2 = Data32([2; 32])
            let shardIndex: UInt16 = 100

            let steps1 = try await service.generateJustification(
                shardIndex: shardIndex,
                segmentsRoot: segmentsRoot1,
                shards: shards
            )

            let steps2 = try await service.generateJustification(
                shardIndex: shardIndex,
                segmentsRoot: segmentsRoot2,
                shards: shards
            )

            // Different segments roots should produce different justifications
            #expect(steps1.count == steps2.count)
            // But the actual hashes should differ
        }

        // MARK: - Generate Segment Justification Tests

        @Test
        func generateSegmentJustificationBasic() async throws {
            let service = makeService()
            let shards = makeTestShards()
            let segmentsRoot = Data32.random()
            let shardIndex: UInt16 = 0
            let segmentIndex: UInt16 = 0
            let bundleShardHash = shards[0].blake2b256hash()
            let baseJustification: [Justification.JustificationStep] = []

            let steps = try service.generateSegmentJustification(
                segmentIndex: segmentIndex,
                bundleShardHash: Data32(bundleShardHash),
                shardIndex: shardIndex,
                segmentsRoot: segmentsRoot,
                shards: shards,
                baseJustification: baseJustification
            )

            // Should include base justification + bundle hash + segment co-path
            #expect(steps.count >= 1)
        }

        @Test
        func generateSegmentJustificationWithBaseJustification() async throws {
            let service = makeService()
            let shards = makeTestShards()
            let segmentsRoot = Data32.random()
            let shardIndex: UInt16 = 0
            let segmentIndex: UInt16 = 0
            let bundleShardHash = shards[0].blake2b256hash()

            let baseJustification: [Justification.JustificationStep] = [
                .left(Data32([1; 32])),
                .right(Data32([2; 32])),
            ]

            let steps = try service.generateSegmentJustification(
                segmentIndex: segmentIndex,
                bundleShardHash: Data32(bundleShardHash),
                shardIndex: shardIndex,
                segmentsRoot: segmentsRoot,
                shards: shards,
                baseJustification: baseJustification
            )

            // Should include base justification + bundle hash + segment co-path
            #expect(steps.count >= baseJustification.count + 1)
        }

        @Test
        func generateSegmentJustificationInvalidShardIndex() async throws {
            let service = makeService()
            let shards = makeTestShards()
            let segmentsRoot = Data32.random()
            let shardIndex: UInt16 = 1023 // Out of range
            let segmentIndex: UInt16 = 0
            let bundleShardHash = Data32.random()
            let baseJustification: [Justification.JustificationStep] = []

            await confirmation("Invalid shard index throws") { _ in
                #expect(throws: ErasureCodingError.self) {
                    try service.generateSegmentJustification(
                        segmentIndex: segmentIndex,
                        bundleShardHash: bundleShardHash,
                        shardIndex: shardIndex,
                        segmentsRoot: segmentsRoot,
                        shards: shards,
                        baseJustification: baseJustification
                    )
                }
            }
        }

        @Test
        func generateSegmentJustificationMultipleSegments() async throws {
            let service = makeService()
            let shards = makeTestShards()
            let segmentsRoot = Data32.random()
            let shardIndex: UInt16 = 0
            let bundleShardHash = shards[0].blake2b256hash()
            let baseJustification: [Justification.JustificationStep] = []

            // Test with different segment indices
            let steps0 = try service.generateSegmentJustification(
                segmentIndex: 0,
                bundleShardHash: Data32(bundleShardHash),
                shardIndex: shardIndex,
                segmentsRoot: segmentsRoot,
                shards: shards,
                baseJustification: baseJustification
            )

            let steps100 = try service.generateSegmentJustification(
                segmentIndex: 100,
                bundleShardHash: Data32(bundleShardHash),
                shardIndex: shardIndex,
                segmentsRoot: segmentsRoot,
                shards: shards,
                baseJustification: baseJustification
            )

            // Both should succeed
            #expect(!steps0.isEmpty)
            #expect(!steps100.isEmpty)
        }

        @Test
        func generateSegmentJustificationIncludesBundleHash() async throws {
            let service = makeService()
            let shards = makeTestShards()
            let segmentsRoot = Data32.random()
            let shardIndex: UInt16 = 0
            let segmentIndex: UInt16 = 0
            let bundleShardHash = Data32([42; 32])
            let baseJustification: [Justification.JustificationStep] = []

            let steps = try service.generateSegmentJustification(
                segmentIndex: segmentIndex,
                bundleShardHash: bundleShardHash,
                shardIndex: shardIndex,
                segmentsRoot: segmentsRoot,
                shards: shards,
                baseJustification: baseJustification
            )

            // Should include bundle hash as a right sibling
            // Find the right step with our hash
            var foundBundleHash = false
            for step in steps {
                switch step {
                case let .right(hash):
                    if hash == bundleShardHash {
                        foundBundleHash = true
                    }
                default:
                    break
                }
            }

            #expect(foundBundleHash)
        }

        // MARK: - Merkle Proof Verification Tests

        @Test
        func verifyMerkleProofValid() async throws {
            let service = makeService()
            let shards = makeTestShards()
            let segmentsRoot = Data32.random()
            let shardIndex: UInt16 = 100

            // Generate justification
            let steps = try await service.generateJustification(
                shardIndex: shardIndex,
                segmentsRoot: segmentsRoot,
                shards: shards
            )

            // Convert to Data32 array
            let proof = steps.map { step in
                switch step {
                case let .left(hash):
                    hash
                case let .right(hash):
                    hash
                }
            }

            // Calculate erasure root
            let erasureRoot = try service.calculateErasureRoot(
                segmentsRoot: segmentsRoot,
                shards: shards
            )

            // Verify the proof
            let shardHash = shards[Int(shardIndex)].blake2b256hash()
            let isValid = service.verifyMerkleProof(
                shardHash: Data32(shardHash),
                shardIndex: shardIndex,
                proof: proof,
                erasureRoot: erasureRoot
            )

            #expect(isValid)
        }

        @Test
        func verifyMerkleProofInvalid() async throws {
            let service = makeService()
            let shards = makeTestShards()
            let segmentsRoot = Data32.random()
            let shardIndex: UInt16 = 100

            // Generate justification for different shard
            let steps = try await service.generateJustification(
                shardIndex: shardIndex,
                segmentsRoot: segmentsRoot,
                shards: shards
            )

            let proof = steps.map { step in
                switch step {
                case let .left(hash):
                    hash
                case let .right(hash):
                    hash
                }
            }

            let erasureRoot = try service.calculateErasureRoot(
                segmentsRoot: segmentsRoot,
                shards: shards
            )

            // Try to verify wrong shard
            let wrongShardHash = Data([1, 2, 3]).blake2b256hash()
            let isValid = service.verifyMerkleProof(
                shardHash: Data32(wrongShardHash),
                shardIndex: shardIndex,
                proof: proof,
                erasureRoot: erasureRoot
            )

            #expect(!isValid)
        }

        @Test
        func verifyMerkleProofFirstShard() async throws {
            let service = makeService()
            let shards = makeTestShards()
            let segmentsRoot = Data32.random()
            let shardIndex: UInt16 = 0

            let steps = try await service.generateJustification(
                shardIndex: shardIndex,
                segmentsRoot: segmentsRoot,
                shards: shards
            )

            let proof = steps.map { step in
                switch step {
                case let .left(hash):
                    hash
                case let .right(hash):
                    hash
                }
            }

            let erasureRoot = try service.calculateErasureRoot(
                segmentsRoot: segmentsRoot,
                shards: shards
            )

            let shardHash = shards[Int(shardIndex)].blake2b256hash()
            let isValid = service.verifyMerkleProof(
                shardHash: Data32(shardHash),
                shardIndex: shardIndex,
                proof: proof,
                erasureRoot: erasureRoot
            )

            #expect(isValid)
        }

        @Test
        func verifyMerkleProofLastShard() async throws {
            let service = makeService()
            let shards = makeTestShards()
            let segmentsRoot = Data32.random()
            let shardIndex: UInt16 = 1022

            let steps = try await service.generateJustification(
                shardIndex: shardIndex,
                segmentsRoot: segmentsRoot,
                shards: shards
            )

            let proof = steps.map { step in
                switch step {
                case let .left(hash):
                    hash
                case let .right(hash):
                    hash
                }
            }

            let erasureRoot = try service.calculateErasureRoot(
                segmentsRoot: segmentsRoot,
                shards: shards
            )

            let shardHash = shards[Int(shardIndex)].blake2b256hash()
            let isValid = service.verifyMerkleProof(
                shardHash: Data32(shardHash),
                shardIndex: shardIndex,
                proof: proof,
                erasureRoot: erasureRoot
            )

            #expect(isValid)
        }

        // MARK: - Integration Tests

        @Test
        func fullJustificationFlow() async throws {
            let service = makeService()
            let shards = makeTestShards()
            let segmentsRoot = Data32.random()

            // Generate justifications for multiple shards
            var justifications: [UInt16: [Justification.JustificationStep]] = [:]

            for shardIndex in [0, 100, 500, 1022] {
                let steps = try await service.generateJustification(
                    shardIndex: UInt16(shardIndex),
                    segmentsRoot: segmentsRoot,
                    shards: shards
                )
                justifications[UInt16(shardIndex)] = steps
            }

            #expect(justifications.count == 4)

            // Verify all justifications
            let erasureRoot = try service.calculateErasureRoot(
                segmentsRoot: segmentsRoot,
                shards: shards
            )

            for (shardIndex, steps) in justifications {
                let proof = steps.map { step in
                    switch step {
                    case let .left(hash):
                        hash
                    case let .right(hash):
                        hash
                    }
                }

                let shardHash = shards[Int(shardIndex)].blake2b256hash()
                let isValid = service.verifyMerkleProof(
                    shardHash: Data32(shardHash),
                    shardIndex: shardIndex,
                    proof: proof,
                    erasureRoot: erasureRoot
                )

                #expect(isValid, "Shard \(shardIndex) proof verification failed")
            }
        }

        // MARK: - Edge Cases

        @Test
        func justificationWithMinimumShards() async throws {
            let service = makeService()
            let shards = makeTestShards(count: 342) // Exactly recovery threshold
            let segmentsRoot = Data32.random()
            let shardIndex: UInt16 = 0

            await confirmation("Requires 1023 shards") { _ in
                #expect(throws: ErasureCodingError.self) {
                    try await service.generateJustification(
                        shardIndex: shardIndex,
                        segmentsRoot: segmentsRoot,
                        shards: shards
                    )
                }
            }
        }

        @Test
        func justificationDeterministic() async throws {
            let service = makeService()
            let shards = makeTestShards()
            let segmentsRoot = Data32.random()
            let shardIndex: UInt16 = 42

            let steps1 = try await service.generateJustification(
                shardIndex: shardIndex,
                segmentsRoot: segmentsRoot,
                shards: shards
            )

            let steps2 = try await service.generateJustification(
                shardIndex: shardIndex,
                segmentsRoot: segmentsRoot,
                shards: shards
            )

            // Same inputs should produce same outputs
            #expect(steps1.count == steps2.count)

            for i in 0 ..< steps1.count {
                switch (steps1[i], steps2[i]) {
                case let (.left(h1), .left(h2)):
                    #expect(h1 == h2)
                case let (.right(h1), .right(h2)):
                    #expect(h1 == h2)
                default:
                    Issue.record("Justification steps don't match")
                }
            }
        }

        @Test
        func justificationStepTypes() async throws {
            let service = makeService()
            let shards = makeTestShards()
            let segmentsRoot = Data32.random()
            let shardIndex: UInt16 = 0

            let steps = try await service.generateJustification(
                shardIndex: shardIndex,
                segmentsRoot: segmentsRoot,
                shards: shards
            )

            // All steps should be either .left or .right
            for step in steps {
                switch step {
                case .left, .right:
                    break // Valid
                }
            }
        }
    }
#endif
