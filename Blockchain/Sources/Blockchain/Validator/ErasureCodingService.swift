import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "ErasureCodingService")

/// Service for erasure coding operations following GP specification
///
/// Implements Reed-Solomon erasure coding in GF(2¹⁶) with rate 342:1023
/// as specified in GP section 10 (erasure_coding.tex)
public actor ErasureCodingService {
    private let config: ProtocolConfigRef

    // Constants from GP spec
    private let originalShardCount = 342
    private let totalShardCount = 1023
    private let pieceSize = 684 // bytes (2 octet pairs)

    public init(config: ProtocolConfigRef) {
        self.config = config
    }

    // MARK: - Encoding

    /// Encode segments into erasure-coded shards
    ///
    /// Each segment is 4,104 bytes = 6 × 684-byte pieces
    /// This encodes segments individually as per GP spec
    ///
    /// - Parameter segments: Array of 4,104-byte segments
    /// - Returns: Array of 1,023 shard data chunks
    /// - Throws: ErasureCodingError if encoding fails
    public func encodeSegments(_ segments: [Data4104]) throws -> [Data] {
        guard !segments.isEmpty else {
            throw ErasureCodingError.emptyInput
        }

        logger.debug("Encoding \(segments.count) segments into shards")

        // Each segment is 4,104 bytes = 6 pieces of 684 bytes each
        // We encode all segments together as a batch
        let totalData = segments.map(\.data).reduce(Data(), +)

        // Calculate k (original pieces)
        let totalPieces = totalData.count / pieceSize

        guard totalPieces * pieceSize == totalData.count else {
            throw ErasureCodingError.invalidDataLength(
                expected: pieceSize,
                actual: totalData.count % pieceSize
            )
        }

        // Encode using existing ErasureCoding utility
        let shards = try ErasureCoding.chunk(
            data: totalData,
            basicSize: pieceSize,
            recoveryCount: totalShardCount
        )

        logger.debug("Generated \(shards.count) shards from \(segments.count) segments")

        return shards
    }

    /// Encode a data blob into erasure-coded shards
    ///
    /// - Parameter data: Data blob (must be multiple of 684 bytes)
    /// - Returns: Array of 1,023 shard data chunks
    /// - Throws: ErasureCodingError if encoding fails
    public func encodeBlob(_ data: Data) throws -> [Data] {
        guard !data.isEmpty else {
            throw ErasureCodingError.emptyInput
        }

        // Validate data size is multiple of 684 bytes
        guard data.count % pieceSize == 0 else {
            throw ErasureCodingError.invalidDataLength(
                expected: pieceSize,
                actual: data.count % pieceSize
            )
        }

        logger.debug("Encoding blob of \(data.count) bytes")

        let shards = try ErasureCoding.chunk(
            data: data,
            basicSize: pieceSize,
            recoveryCount: totalShardCount
        )

        logger.debug("Generated \(shards.count) shards")

        return shards
    }

    // MARK: - Decoding

    /// Reconstruct original data from shards
    ///
    /// - Parameters:
    ///   - shards: Array of (index, data) tuples
    ///   - originalLength: Expected original data length
    /// - Returns: Reconstructed original data
    /// - Throws: ErasureCodingError if reconstruction fails
    public func reconstruct(shards: [(index: UInt16, data: Data)], originalLength: Int) throws -> Data {
        guard shards.count >= originalShardCount else {
            throw ErasureCodingError.insufficientShards(
                required: originalShardCount,
                provided: shards.count
            )
        }

        // Validate shard indices are unique
        let indices = shards.map(\.index)
        let uniqueIndices = Set(indices)
        guard uniqueIndices.count == indices.count else {
            throw ErasureCodingError.duplicateShardIndices
        }

        logger.debug("Reconstructing from \(shards.count) shards (target length: \(originalLength))")

        // Convert to ErasureCoding.Shard format
        let erasureShards = shards.map { shard in
            ErasureCoding.Shard(data: shard.data, index: UInt32(shard.index))
        }

        // Calculate original count (approximately 1/3 of recovery count)
        let originalCount = (totalShardCount + 2) / 3

        do {
            let reconstructed = try ErasureCoding.reconstruct(
                shards: erasureShards,
                basicSize: pieceSize,
                originalCount: originalCount,
                recoveryCount: totalShardCount,
                originalLength: originalLength
            )

            logger.debug("Successfully reconstructed \(reconstructed.count) bytes")

            return reconstructed
        } catch {
            logger.error("Failed to reconstruct data: \(error)")
            throw ErasureCodingError.reconstructionFailed(underlying: error)
        }
    }

    /// Reconstruct segments from shards
    ///
    /// - Parameters:
    ///   - shards: Array of (index, data) tuples
    ///   - segmentCount: Expected number of segments
    /// - Returns: Array of reconstructed 4,104-byte segments
    /// - Throws: ErasureCodingError if reconstruction fails
    public func reconstructSegments(
        shards: [(index: UInt16, data: Data)],
        segmentCount: Int
    ) throws -> [Data4104] {
        let totalDataSize = segmentCount * 4104

        let reconstructedData = try reconstruct(
            shards: shards,
            originalLength: totalDataSize
        )

        // Split into segments
        var segments: [Data4104] = []

        for i in 0 ..< segmentCount {
            let start = i * 4104
            let end = min(start + 4104, reconstructedData.count)
            let segmentData = Data(reconstructedData[start ..< end])

            // Pad if necessary
            var paddedSegment = segmentData
            if paddedSegment.count < 4104 {
                paddedSegment.append(Data(count: 4104 - paddedSegment.count))
            }

            guard let segment = Data4104(paddedSegment) else {
                throw ErasureCodingError.invalidSegmentLength(
                    expected: 4104,
                    actual: paddedSegment.count
                )
            }

            segments.append(segment)
        }

        logger.debug("Reconstructed \(segments.count) segments")

        return segments
    }

    // MARK: - Erasure Root Calculation

    /// Calculate erasure root for segments
    ///
    /// Per GP spec: For each shard, compute hash(shard) || segmentsRoot,
    /// then calculate binary Merkle root of all nodes
    ///
    /// - Parameters:
    ///   - segmentsRoot: Merkle root of segments
    ///   - shards: Array of shard data
    /// - Returns: Erasure root (Data32)
    /// - Throws: ErasureCodingError if calculation fails
    public func calculateErasureRoot(segmentsRoot: Data32, shards: [Data]) throws -> Data32 {
        guard shards.count == totalShardCount else {
            throw ErasureCodingError.invalidShardCount(
                expected: totalShardCount,
                provided: shards.count
            )
        }

        // Generate nodes: encode(shardHash) || encode(segmentsRoot)
        var nodes: [Data] = []

        for shard in shards {
            let shardHash = shard.blake2b256hash()
            let node = JamEncoder.encode(shardHash) + JamEncoder.encode(segmentsRoot)
            nodes.append(node)
        }

        // Calculate binary Merkle root
        let erasureRoot = Merklization.binaryMerklize(nodes)

        logger.debug("Calculated erasure root for \(shards.count) shards")

        return erasureRoot
    }
}

// MARK: - Errors

public enum ErasureCodingError: Error {
    case emptyInput
    case invalidDataLength(expected: Int, actual: Int)
    case insufficientShards(required: Int, provided: Int)
    case duplicateShardIndices
    case invalidShardCount(expected: Int, provided: Int)
    case invalidSegmentLength(expected: Int, actual: Int)
    case reconstructionFailed(underlying: Error)
    case merkleProofGenerationFailed
    case invalidMerkleProof
}

// MARK: - Merkle Proof Generation

extension ErasureCodingService {
    /// Generate Merkle proof for a shard
    ///
    /// - Parameters:
    ///   - shardIndex: Index of the shard (0-1022)
    ///   - shardHashes: Array of all shard hashes
    /// - Returns: Array of sibling hashes for the proof path
    /// - Throws: ErasureCodingError if proof generation fails
    public func generateMerkleProof(shardIndex: UInt16, shardHashes: [Data32]) throws -> [Data32] {
        guard shardIndex < UInt16(shardHashes.count) else {
            throw ErasureCodingError.invalidShardIndex
        }

        let proof = Merklization.trace(
            shardHashes.map(\.data),
            index: Int(shardIndex),
            hasher: Blake2b256.self
        )

        // Convert MerklePath to array of hashes
        var hashes: [Data32] = []

        for step in proof {
            switch step {
            case let .left(hash):
                guard let data32 = Data32(hash) else {
                    throw ErasureCodingError.merkleProofGenerationFailed
                }
                hashes.append(data32)
            case let .right(hash):
                guard let data32 = Data32(hash) else {
                    throw ErasureCodingError.merkleProofGenerationFailed
                }
                hashes.append(data32)
            }
        }

        logger.debug("Generated Merkle proof for shard \(shardIndex) with \(hashes.count) steps")

        return hashes
    }

    /// Verify Merkle proof for a shard
    ///
    /// - Parameters:
    ///   - shardHash: Hash of the shard to verify
    ///   - shardIndex: Index of the shard (0-1022)
    ///   - proof: Merkle proof path
    ///   - erasureRoot: Expected erasure root
    /// - Returns: True if proof is valid
    public func verifyMerkleProof(
        shardHash: Data32,
        shardIndex: UInt16,
        proof: [Data32],
        erasureRoot: Data32
    ) -> Bool {
        // Start with shard hash
        var currentValue = shardHash

        // Walk the proof path
        for (i, proofElement) in proof.enumerated() {
            // Determine if we're on the left or right at this level
            let bitSet = (Int(shardIndex) >> i) & 1

            if bitSet == 0 {
                // Current value is on the left
                let combined = currentValue.data + proofElement.data
                currentValue = combined.blake2b256hash()
            } else {
                // Current value is on the right
                let combined = proofElement.data + currentValue.data
                currentValue = combined.blake2b256hash()
            }
        }

        let isValid = currentValue == erasureRoot

        if isValid {
            logger.trace("Merkle proof verified for shard \(shardIndex)")
        } else {
            logger.warning("Merkle proof verification failed for shard \(shardIndex)")
        }

        return isValid
    }
}
