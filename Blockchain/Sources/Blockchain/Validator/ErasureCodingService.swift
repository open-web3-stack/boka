import Codec
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
    /// Per GP spec (erasure_coding.tex eq. 32-35), this:
    /// 1. Concatenates all segments into a single data blob
    /// 2. Transposes the data (via the ^T operator in the spec)
    /// 3. Erasure codes the transposed data into 1,023 shards
    ///
    /// The transposition ensures that each shard contains interleaved data from all segments,
    /// allowing efficient parallel recovery. After transposition and encoding, shard i contains
    /// piece i from each segment, making it possible to recover any segment from any 342 shards.
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
        // Per GP spec: concatenate all segments, then transpose and encode
        // The ErasureCoding.chunk function handles the transposition as part of encoding
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
        // This handles the transposition (^T operator) per GP spec
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
            let encodedShardHash = try JamEncoder.encode(shardHash)
            let encodedSegmentsRoot = try JamEncoder.encode(segmentsRoot)
            let node = encodedShardHash + encodedSegmentsRoot
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
    case invalidShardIndex
    case invalidShardCount(expected: Int, provided: Int)
    case invalidSegmentLength(expected: Int, actual: Int)
    case reconstructionFailed(underlying: Error)
    case merkleProofGenerationFailed
    case invalidMerkleProof
    case invalidHash
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
            case let .left(data):
                // Convert Data to Data32
                guard let hash = Data32(data) else {
                    throw ErasureCodingError.invalidHash
                }
                hashes.append(hash)
            case let .right(hash):
                hashes.append(hash)
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

    // MARK: - JAMNP-S Justification Generation

    /// Generate JAMNP-S justification for CE 137 (Shard Distribution)
    ///
    /// Per JAMNP-S spec, this generates the co-path T(s, i, H) where:
    /// - s is the sequence of (bundle shard hash, segment shard root) pairs
    /// - i is the shard index
    /// - H is the Blake2b hash function
    ///
    /// - Parameters:
    ///   - shardIndex: Index of the shard (0-1022)
    ///   - segmentsRoot: Merkle root of segments
    ///   - shards: Array of all shard data
    /// - Returns: Array of justification steps (co-path)
    /// - Throws: ErasureCodingError if justification generation fails
    public func generateJustification(
        shardIndex: UInt16,
        segmentsRoot: Data32,
        shards: [Data]
    ) throws -> [AvailabilityJustification.AvailabilityJustificationStep] {
        guard shardIndex < UInt16(shards.count) else {
            throw ErasureCodingError.invalidShardIndex
        }

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
            let encodedShardHash = try JamEncoder.encode(shardHash)
            let encodedSegmentsRoot = try JamEncoder.encode(segmentsRoot)
            let node = encodedShardHash + encodedSegmentsRoot
            nodes.append(node)
        }

        // Generate co-path using T(s, i, H) function
        let copath = Merklization.trace(
            nodes,
            index: Int(shardIndex),
            hasher: Blake2b256.self
        )

        // Convert to JustificationSteps
        var steps: [AvailabilityJustification.AvailabilityJustificationStep] = []

        for step in copath {
            switch step {
            case let .left(data):
                // Convert Data to Data32
                guard let hash = Data32(data) else {
                    throw ErasureCodingError.invalidHash
                }
                steps.append(.left(hash))
            case let .right(hash):
                steps.append(.right(hash))
            }
        }

        logger.debug("Generated JAMNP-S justification for shard \(shardIndex) with \(steps.count) steps")

        return steps
    }

    /// Generate JAMNP-S justification for CE 140 (Segment Shard Request with justification)
    ///
    /// Per JAMNP-S spec, this generates: j ++ [b] ++ T(s, i, H) where:
    /// - j is the justification from CE 137
    /// - b is the bundle shard hash
    /// - s is the full sequence of segment shards with the given shard index
    /// - i is the segment index
    ///
    /// - Parameters:
    ///   - segmentIndex: Index of the segment
    ///   - bundleShardHash: Hash of the bundle shard
    ///   - shardIndex: Index of the shard (0-1022)
    ///   - segmentsRoot: Merkle root of segments
    ///   - shards: Array of all shard data
    ///   - baseJustification: Justification received from CE 137
    /// - Returns: Complete justification for CE 140
    /// - Throws: ErasureCodingError if justification generation fails
    public func generateSegmentJustification(
        segmentIndex: UInt16,
        bundleShardHash: Data32,
        shardIndex: UInt16,
        segmentsRoot _: Data32,
        shards: [Data],
        baseJustification: [AvailabilityJustification.AvailabilityJustificationStep]
    ) throws -> [AvailabilityJustification.AvailabilityJustificationStep] {
        // Generate the segment co-path T(s, i, H) for the segment shards
        // The segment shards form a sequence at the same shard index across all segments

        guard Int(shardIndex) < shards.count else {
            throw ErasureCodingError.invalidShardIndex
        }

        // Calculate segment shard size from constants
        // Each segment is 4104 bytes, divided by original shard count (342)
        let segmentShardSize = 4104 / originalShardCount

        var segmentShards: [Data] = []
        for shard in shards {
            let offset = Int(segmentIndex) * segmentShardSize
            let endOffset = min(offset + segmentShardSize, shard.count)
            if offset < shard.count {
                let segmentShard = Data(shard[offset ..< endOffset])
                segmentShards.append(segmentShard)
            }
        }

        // Generate co-path for segment shards
        let segmentCopath = Merklization.trace(
            segmentShards,
            index: Int(shardIndex),
            hasher: Blake2b256.self
        )

        // Combine: baseJustification ++ [bundleShardHash] ++ segmentCopath
        var fullJustification = baseJustification

        // Insert bundle shard hash as a right sibling
        fullJustification.append(.right(bundleShardHash))

        // Add segment co-path steps
        for step in segmentCopath {
            switch step {
            case let .left(data):
                // Convert Data to Data32
                guard let hash = Data32(data) else {
                    throw ErasureCodingError.invalidHash
                }
                fullJustification.append(.left(hash))
            case let .right(hash):
                fullJustification.append(.right(hash))
            }
        }

        logger.debug("Generated segment justification with \(fullJustification.count) steps")

        return fullJustification
    }
}
