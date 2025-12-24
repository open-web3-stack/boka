import Foundation
import Testing
import TracingUtils
import Utils

@testable import Blockchain

struct ErasureCodingServiceTests {
    func makeService() -> ErasureCodingService {
        ErasureCodingService(config: .dev)
    }

    // MARK: - Encoding Tests

    @Test
    func encodeSingleSegment() async throws {
        let service = makeService()

        // Create a test segment (4,104 bytes = 6 × 684 bytes)
        var segmentData = Data(count: 4104)
        for i in 0 ..< 4104 {
            segmentData[i] = UInt8(truncatingIfNeeded: i)
        }
        let segment = Data4104(segmentData)!

        // Encode
        let shards = try service.encodeSegments([segment])

        // Should produce 1,023 shards
        #expect(shards.count == 1023)

        // Each shard should be smaller than original segment
        // (original is 4,104 bytes, shards are approximately 1/3 after encoding overhead)
        #expect(shards[0].count > 0)

        // All shards should have same size
        let firstShardSize = shards[0].count
        for shard in shards {
            #expect(shard.count == firstShardSize)
        }
    }

    @Test
    func encodeMultipleSegments() async throws {
        let service = makeService()

        // Create 3 test segments
        var segments: [Data4104] = []
        for segIndex in 0 ..< 3 {
            var segmentData = Data(count: 4104)
            for i in 0 ..< 4104 {
                segmentData[i] = UInt8(truncatingIfNeeded: segIndex * 4104 + i)
            }
            segments.append(Data4104(segmentData)!)
        }

        // Encode
        let shards = try service.encodeSegments(segments)

        // Should produce 1,023 shards
        #expect(shards.count == 1023)
    }

    @Test
    func encodeBlob() async throws {
        let service = makeService()

        // Create a test blob (must be multiple of 684 bytes)
        let blobSize = 684 * 10 // 10 pieces
        var blobData = Data(count: blobSize)
        for i in 0 ..< blobSize {
            blobData[i] = UInt8(truncatingIfNeeded: i)
        }

        // Encode
        let shards = try service.encodeBlob(blobData)

        // Should produce 1,023 shards
        #expect(shards.count == 1023)
    }

    @Test
    func encodeEmptyInputThrowsError() async throws {
        let service = makeService()

        // Try to encode empty array
        #expect(throws: ErasureCodingError.self) {
            try service.encodeSegments([])
        }

        #expect(throws: ErasureCodingError.self) {
            try service.encodeBlob(Data())
        }
    }

    @Test
    func encodeInvalidLengthThrowsError() async throws {
        let service = makeService()

        // Try to encode data that's not a multiple of 684 bytes
        let invalidData = Data(count: 100) // Not divisible by 684

        #expect(throws: ErasureCodingError.self) {
            try service.encodeBlob(invalidData)
        }
    }

    // MARK: - Decoding Tests

    @Test
    func reconstructFromAllShards() async throws {
        let service = makeService()

        // Create and encode test data
        let originalData = Data(count: 684 * 10)
        let shards = try service.encodeBlob(originalData)

        // Reconstruct from all shards
        let shardTuples = shards.enumerated().map { index, data in
            (index: UInt16(index), data: data)
        }

        let reconstructed = try service.reconstruct(
            shards: shardTuples,
            originalLength: originalData.count
        )

        // Should reconstruct to original
        #expect(reconstructed == originalData)
    }

    @Test
    func reconstructFrom342Shards() async throws {
        let service = makeService()

        // Create and encode test data
        let originalData = Data(count: 684 * 10)
        let shards = try service.encodeBlob(originalData)

        // Take only first 342 shards (minimum required)
        let partialShards = Array(shards.prefix(342))
        let shardTuples = partialShards.enumerated().map { index, data in
            (index: UInt16(index), data: data)
        }

        let reconstructed = try service.reconstruct(
            shards: shardTuples,
            originalLength: originalData.count
        )

        // Should reconstruct to original
        #expect(reconstructed == originalData)
    }

    @Test
    func reconstructFrom500Shards() async throws {
        let service = makeService()

        // Create and encode test data
        let originalData = Data(count: 684 * 20)
        let shards = try service.encodeBlob(originalData)

        // Take 500 random shards
        var randomShards = shards
        randomShards.shuffle()
        let partialShards = Array(randomShards.prefix(500))
        let shardTuples = partialShards.enumerated().map { index, data in
            (index: UInt16(index), data: data)
        }

        let reconstructed = try service.reconstruct(
            shards: shardTuples,
            originalLength: originalData.count
        )

        // Should reconstruct to original
        #expect(reconstructed == originalData)
    }

    @Test
    func reconstructFromInsufficientShardsThrowsError() async throws {
        let service = makeService()

        // Create and encode test data
        let originalData = Data(count: 684 * 10)
        let shards = try service.encodeBlob(originalData)

        // Take only 300 shards (insufficient)
        let partialShards = Array(shards.prefix(300))
        let shardTuples = partialShards.enumerated().map { index, data in
            (index: UInt16(index), data: data)
        }

        #expect(throws: ErasureCodingError.self) {
            try service.reconstruct(
                shards: shardTuples,
                originalLength: originalData.count
            )
        }
    }

    @Test
    func reconstructSegments() async throws {
        let service = makeService()

        // Create test segments
        var segments: [Data4104] = []
        for segIndex in 0 ..< 3 {
            var segmentData = Data(count: 4104)
            for i in 0 ..< 4104 {
                segmentData[i] = UInt8(truncatingIfNeeded: segIndex * 4104 + i)
            }
            segments.append(Data4104(segmentData)!)
        }

        // Encode
        let shards = try service.encodeSegments(segments)
        let shardTuples = shards.enumerated().map { index, data in
            (index: UInt16(index), data: data)
        }

        // Reconstruct
        let reconstructedSegments = try service.reconstructSegments(
            shards: shardTuples,
            segmentCount: 3
        )

        // Should reconstruct to original
        #expect(reconstructedSegments.count == 3)
        for i in 0 ..< 3 {
            #expect(reconstructedSegments[i] == segments[i])
        }
    }

    // MARK: - Erasure Root Tests

    @Test
    func calculateErasureRoot() async throws {
        let service = makeService()

        // Create test data
        let originalData = Data(count: 684 * 10)
        let shards = try service.encodeBlob(originalData)
        let segmentsRoot = Data32.random()

        // Calculate erasure root
        let erasureRoot = try service.calculateErasureRoot(
            segmentsRoot: segmentsRoot,
            shards: shards
        )

        // Should be a valid 32-byte hash
        #expect(erasureRoot.data.count == 32)

        // Same input should produce same erasure root
        let erasureRoot2 = try service.calculateErasureRoot(
            segmentsRoot: segmentsRoot,
            shards: shards
        )
        #expect(erasureRoot == erasureRoot2)
    }

    @Test
    func calculateErasureRootDifferentSegmentsRoot() async throws {
        let service = makeService()

        let originalData = Data(count: 684 * 10)
        let shards = try service.encodeBlob(originalData)

        let segmentsRoot1 = Data32.random()
        let segmentsRoot2 = Data32.random()

        let erasureRoot1 = try service.calculateErasureRoot(
            segmentsRoot: segmentsRoot1,
            shards: shards
        )
        let erasureRoot2 = try service.calculateErasureRoot(
            segmentsRoot: segmentsRoot2,
            shards: shards
        )

        // Different segments roots should produce different erasure roots
        #expect(erasureRoot1 != erasureRoot2)
    }

    @Test
    func calculateErasureRootInvalidShardCount() async throws {
        let service = makeService()

        let segmentsRoot = Data32.random()
        let invalidShards = Array(repeating: Data(count: 100), count: 100)

        #expect(throws: ErasureCodingError.self) {
            try service.calculateErasureRoot(
                segmentsRoot: segmentsRoot,
                shards: invalidShards
            )
        }
    }

    // MARK: - Merkle Proof Tests

    @Test
    func generateAndVerifyMerkleProof() async throws {
        let service = makeService()

        // Create test data
        let originalData = Data(count: 684 * 10)
        let shards = try service.encodeBlob(originalData)

        // Calculate shard hashes
        let shardHashes: [Data32] = shards.map { $0.blake2b256hash() }

        // Generate proof for shard 0
        let proof = try service.generateMerkleProof(shardIndex: 0, shardHashes: shardHashes)

        // Proof should not be empty
        #expect(!proof.isEmpty)

        // Verify proof
        let isValid = try service.verifyMerkleProof(
            shardHash: shardHashes[0],
            shardIndex: 0,
            proof: proof,
            erasureRoot: service.calculateErasureRoot(
                segmentsRoot: Data32.random(),
                shards: shards
            )
        )

        #expect(isValid)
    }

    @Test
    func generateMerkleProofForMiddleShard() async throws {
        let service = makeService()

        let originalData = Data(count: 684 * 10)
        let shards = try service.encodeBlob(originalData)
        let shardHashes: [Data32] = shards.map { $0.blake2b256hash() }

        // Generate proof for middle shard (511)
        let proof = try service.generateMerkleProof(shardIndex: 511, shardHashes: shardHashes)

        #expect(!proof.isEmpty)

        let erasureRoot = try service.calculateErasureRoot(
            segmentsRoot: Data32.random(),
            shards: shards
        )

        let isValid = service.verifyMerkleProof(
            shardHash: shardHashes[511],
            shardIndex: 511,
            proof: proof,
            erasureRoot: erasureRoot
        )

        #expect(isValid)
    }

    @Test
    func verifyInvalidMerkleProof() async throws {
        let service = makeService()

        let originalData = Data(count: 684 * 10)
        let shards = try service.encodeBlob(originalData)
        let shardHashes: [Data32] = shards.map { $0.blake2b256hash() }
        let erasureRoot = try service.calculateErasureRoot(
            segmentsRoot: Data32.random(),
            shards: shards
        )

        // Create fake proof
        let fakeProof = Array(repeating: Data32.random(), count: 10)

        let isValid = service.verifyMerkleProof(
            shardHash: shardHashes[0],
            shardIndex: 0,
            proof: fakeProof,
            erasureRoot: erasureRoot
        )

        #expect(!isValid)
    }

    @Test
    func verifyMerkleProofWrongShard() async throws {
        let service = makeService()

        let originalData = Data(count: 684 * 10)
        let shards = try service.encodeBlob(originalData)
        let shardHashes: [Data32] = shards.map { $0.blake2b256hash() }

        let proof = try service.generateMerkleProof(shardIndex: 0, shardHashes: shardHashes)
        let erasureRoot = try service.calculateErasureRoot(
            segmentsRoot: Data32.random(),
            shards: shards
        )

        // Try to verify shard 0 proof with shard 1 hash
        let isValid = service.verifyMerkleProof(
            shardHash: shardHashes[1],
            shardIndex: 0,
            proof: proof,
            erasureRoot: erasureRoot
        )

        #expect(!isValid)
    }

    @Test
    func generateMerkleProofInvalidIndex() async throws {
        let service = makeService()

        let originalData = Data(count: 684 * 10)
        let shards = try service.encodeBlob(originalData)
        let shardHashes: [Data32] = shards.map { $0.blake2b256hash() }

        // Try to generate proof for invalid index
        #expect(throws: ErasureCodingError.self) {
            try service.generateMerkleProof(shardIndex: 2000, shardHashes: shardHashes)
        }
    }
}
