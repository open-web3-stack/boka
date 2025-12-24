import Foundation
import Testing
import TracingUtils
import Utils

@testable import Blockchain

/// Unit tests for ErasureCodingService focusing on individual functions
/// and edge cases without full integration setup
struct ErasureCodingServiceUnitTests {
    func makeService() -> ErasureCodingService {
        ErasureCodingService(config: .dev)
    }

    // MARK: - Encoding Validation Tests

    @Test
    func validateBlobSizeMultiple() {
        let service = makeService()

        // Valid sizes (multiples of 684)
        let validSizes = [684, 1368, 2052, 6840, 13680]

        for size in validSizes {
            let data = Data(count: size)
            // Should not throw for valid sizes
            do {
                _ = try service.encodeBlob(data)
                #expect(true, "Successfully encoded \(size) bytes")
            } catch {
                #expect(Bool(false), "Failed to encode valid size \(size): \(error)")
            }
        }
    }

    @Test
    func encodeEmptyDataThrowsError() {
        let service = makeService()
        let emptyData = Data()

        #expect(throws: ErasureCodingError.self) {
            try service.encodeBlob(emptyData)
        }
    }

    @Test
    func encodeInvalidSizeThrowsError() {
        let service = makeService()

        // Invalid sizes (not multiples of 684)
        let invalidSizes = [1, 100, 683, 685, 1000, 5000]

        for size in invalidSizes {
            let data = Data(count: size)
            // Should throw for invalid sizes
            do {
                _ = try service.encodeBlob(data)
                #expect(Bool(false), "Should have thrown error for size \(size)")
            } catch is ErasureCodingError {
                // Expected
            } catch {
                #expect(Bool(false), "Wrong error type for size \(size): \(error)")
            }
        }
    }

    // MARK: - Shard Count Validation Tests

    @Test
    func validateShardCount() {
        let service = makeService()
        let validData = Data(count: 684 * 10)

        do {
            let shards = try service.encodeBlob(validData)
            #expect(shards.count == 1023, "Should produce exactly 1023 shards")
        } catch {
            #expect(Bool(false), "Encoding failed: \(error)")
        }
    }

    @Test
    func allShardsHaveSameSize() {
        let service = makeService()
        let validData = Data(count: 684 * 10)

        do {
            let shards = try service.encodeBlob(validData)
            #expect(!shards.isEmpty, "Should have shards")

            let firstSize = shards[0].count
            for (index, shard) in shards.enumerated() {
                #expect(
                    shard.count == firstSize,
                    "Shard \(index) has size \(shard.count), expected \(firstSize)"
                )
            }
        } catch {
            #expect(Bool(false), "Encoding failed: \(error)")
        }
    }

    // MARK: - Reconstruction Threshold Tests

    @Test
    func reconstructionThresholds() {
        let minimumRequired = 342
        let totalShards = 1023

        // Test boundary conditions
        #expect(minimumRequired < totalShards, "Minimum should be less than total")

        // Test that we need less than half
        #expect(Double(minimumRequired) / Double(totalShards) < 0.5)

        // Test that we need more than 1/3
        #expect(Double(minimumRequired) / Double(totalShards) > 0.33)
    }

    @Test
    func validateReconstructionShardCounts() {
        let service = makeService()
        let originalData = Data(count: 684 * 10)

        do {
            let shards = try service.encodeBlob(originalData)

            // Test various shard counts around the threshold
            let testCases: [(Int, Bool)] = [
                (300, false), // Below threshold - should fail
                (341, false), // Just below threshold - should fail
                (342, true), // Exactly threshold - should succeed
                (400, true), // Above threshold - should succeed
                (500, true), // Well above threshold - should succeed
                (1023, true), // All shards - should succeed
            ]

            for (shardCount, shouldSucceed) in testCases {
                let partialShards = Array(shards.prefix(shardCount))
                let shardTuples = partialShards.enumerated().map { index, data in
                    (index: UInt16(index), data: data)
                }

                do {
                    _ = try service.reconstruct(
                        shards: shardTuples,
                        originalLength: originalData.count
                    )

                    if shouldSucceed {
                        #expect(true, "Reconstruction with \(shardCount) shards succeeded as expected")
                    } else {
                        #expect(Bool(false), "Reconstruction with \(shardCount) shards should have failed")
                    }
                } catch is ErasureCodingError {
                    if !shouldSucceed {
                        #expect(true, "Reconstruction with \(shardCount) shards failed as expected")
                    } else {
                        #expect(Bool(false), "Reconstruction with \(shardCount) shards should have succeeded")
                    }
                } catch {
                    #expect(Bool(false), "Unexpected error: \(error)")
                }
            }
        } catch {
            #expect(Bool(false), "Setup encoding failed: \(error)")
        }
    }

    // MARK: - Merkle Proof Tests

    @Test
    func validateMerkleProofStructure() {
        let service = makeService()
        let originalData = Data(count: 684 * 10)

        do {
            let shards = try service.encodeBlob(originalData)
            let shardHashes: [Data32] = shards.map { $0.blake2b256hash() }

            // Generate proof for middle shard
            let proof = try service.generateMerkleProof(shardIndex: 511, shardHashes: shardHashes)

            // Proof should not be empty
            #expect(!proof.isEmpty, "Merkle proof should not be empty")

            // Proof should have reasonable depth (log2 of 1023 ≈ 10)
            #expect(proof.count <= 11, "Proof depth should be ≤ 11")

            // All proof elements should be valid hashes
            for hash in proof {
                #expect(hash.data.count == 32, "Each proof element should be 32 bytes")
            }
        } catch {
            #expect(Bool(false), "Merkle proof generation failed: \(error)")
        }
    }

    @Test
    func invalidMerkleProofIndex() {
        let service = makeService()
        let originalData = Data(count: 684 * 10)

        do {
            let shards = try service.encodeBlob(originalData)
            let shardHashes: [Data32] = shards.map { $0.blake2b256hash() }

            // Try to generate proof for invalid index
            #expect(throws: ErasureCodingError.self) {
                try service.generateMerkleProof(shardIndex: 2000, shardHashes: shardHashes)
            }
        } catch {
            #expect(Bool(false), "Setup failed: \(error)")
        }
    }

    @Test
    func verifyInvalidMerkleProof() {
        let service = makeService()
        let originalData = Data(count: 684 * 10)

        do {
            let shards = try service.encodeBlob(originalData)
            let shardHashes: [Data32] = shards.map { $0.blake2b256hash() }
            let erasureRoot = try service.calculateErasureRoot(
                segmentsRoot: Data32.random(),
                shards: shards
            )

            // Generate fake proof
            let fakeProof = Array(repeating: Data32.random(), count: 10)

            // Verify should fail
            let isValid = service.verifyMerkleProof(
                shardHash: shardHashes[0],
                shardIndex: 0,
                proof: fakeProof,
                erasureRoot: erasureRoot
            )

            #expect(!isValid, "Fake proof should fail verification")
        } catch {
            #expect(Bool(false), "Setup failed: \(error)")
        }
    }

    // MARK: - Segment Encoding Tests

    @Test
    func encodeSegmentsWithZeroPadding() {
        let service = makeService()

        // Create segments that aren't exact multiples
        var segments: [Data4104] = []
        for i in 0 ..< 5 {
            var segmentData = Data(count: 4104)
            segmentData[0] = UInt8(truncatingIfNeeded: i)
            segments.append(Data4104(segmentData)!)
        }

        do {
            let shards = try service.encodeSegments(segments)

            // Should produce 1023 shards
            #expect(shards.count == 1023)

            // All shards should have consistent size
            let shardSize = shards[0].count
            for shard in shards {
                #expect(shard.count == shardSize, "All shards should have same size")
            }
        } catch {
            #expect(Bool(false), "Encoding failed: \(error)")
        }
    }

    // MARK: - Erasure Root Tests

    @Test
    func erasureRootDeterminism() {
        let service = makeService()
        let originalData = Data(count: 684 * 10)
        let segmentsRoot = Data32.random()

        do {
            let shards1 = try service.encodeBlob(originalData)
            let erasureRoot1 = try service.calculateErasureRoot(
                segmentsRoot: segmentsRoot,
                shards: shards1
            )

            let shards2 = try service.encodeBlob(originalData)
            let erasureRoot2 = try service.calculateErasureRoot(
                segmentsRoot: segmentsRoot,
                shards: shards2
            )

            // Same input should produce same erasure root
            #expect(
                erasureRoot1 == erasureRoot2,
                "Erasure root should be deterministic"
            )
        } catch {
            #expect(Bool(false), "Setup failed: \(error)")
        }
    }

    @Test
    func erasureRootUniqueness() {
        let service = makeService()
        let segmentsRoot = Data32.random()

        do {
            let data1 = Data(count: 684 * 10)
            let shards1 = try service.encodeBlob(data1)
            let erasureRoot1 = try service.calculateErasureRoot(
                segmentsRoot: segmentsRoot,
                shards: shards1
            )

            let data2 = Data(count: 684 * 20)
            let shards2 = try service.encodeBlob(data2)
            let erasureRoot2 = try service.calculateErasureRoot(
                segmentsRoot: segmentsRoot,
                shards: shards2
            )

            // Different data should produce different erasure roots
            #expect(
                erasureRoot1 != erasureRoot2,
                "Different data should produce different erasure roots"
            )
        } catch {
            #expect(Bool(false), "Setup failed: \(error)")
        }
    }

    // MARK: - Edge Case Tests

    @Test
    func encodeSinglePiece() {
        let service = makeService()
        let singlePiece = Data(count: 684)

        do {
            let shards = try service.encodeBlob(singlePiece)

            #expect(shards.count == 1023, "Should still produce 1023 shards")
            #expect(shards[0].count > 0, "Shards should have data")
        } catch {
            #expect(Bool(false), "Encoding failed: \(error)")
        }
    }

    @Test
    func encodeMaximumSize() {
        let service = makeService()

        // Maximum reasonable size (3072 segments = 12,587,776 bytes)
        let maxData = Data(count: 684 * 3072)

        do {
            let shards = try service.encodeBlob(maxData)

            #expect(shards.count == 1023, "Should produce 1023 shards")
        } catch {
            #expect(Bool(false), "Encoding max size failed: \(error)")
        }
    }

    @Test
    func reconstructWithExactShards() {
        let service = makeService()

        // Create test data with known pattern
        let testData: [UInt8] = [0, 1, 2, 3, 4, 5]
        let data = Data(testData) + Data(count: 684 * 10 - testData.count)

        do {
            let shards = try service.encodeBlob(data)

            // Take exactly 342 shards
            let partialShards = Array(shards.prefix(342))
            let shardTuples = partialShards.enumerated().map { index, data in
                (index: UInt16(index), data: data)
            }

            let reconstructed = try service.reconstruct(
                shards: shardTuples,
                originalLength: data.count
            )

            // Verify reconstruction
            #expect(reconstructed.count == data.count)
            #expect(reconstructed[0] == 0)
            #expect(reconstructed[1] == 1)
            #expect(reconstructed[2] == 2)
        } catch {
            #expect(Bool(false), "Reconstruction failed: \(error)")
        }
    }
}
