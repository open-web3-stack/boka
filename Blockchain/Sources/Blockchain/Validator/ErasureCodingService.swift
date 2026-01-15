import Codec
import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "ErasureCodingService")

/// Reed-Solomon erasure coding (GP spec section 10)
///
/// Implements erasure coding in GF(2¹⁶) with rate 342:1023
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
    /// Each segment is 4,104 bytes = 6 × 684-byte pieces.
    /// Per GP spec: concatenates, transposes (^T operator), and erasure codes into 1,023 shards.
    public func encodeSegments(_ segments: [Data4104]) throws -> [Data] {
        guard !segments.isEmpty else {
            throw ErasureCodingError.emptyInput
        }

        logger.debug("Encoding \(segments.count) segments into shards")

        // Concatenate all segment data efficiently
        // Data with pre-allocated capacity avoids repeated allocations during appends
        var totalData = Data(capacity: segments.count * 4104)
        for segment in segments {
            totalData.append(segment.data)
        }

        let totalPieces = totalData.count / pieceSize

        guard totalPieces * pieceSize == totalData.count else {
            throw ErasureCodingError.invalidDataLength(
                expected: pieceSize,
                actual: totalData.count % pieceSize
            )
        }

        let shards = try ErasureCoding.chunk(
            data: totalData,
            basicSize: pieceSize,
            recoveryCount: totalShardCount
        )

        logger.debug("Generated \(shards.count) shards from \(segments.count) segments")

        return shards
    }

    /// Encode a data blob into erasure-coded shards
    public func encodeBlob(_ data: Data) throws -> [Data] {
        guard !data.isEmpty else {
            throw ErasureCodingError.emptyInput
        }

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
    public func reconstruct(shards: [(index: UInt16, data: Data)], originalLength: Int) throws -> Data {
        guard shards.count >= originalShardCount else {
            throw ErasureCodingError.insufficientShards(
                required: originalShardCount,
                provided: shards.count
            )
        }

        let indices = shards.map(\.index)
        let uniqueIndices = Set(indices)
        guard uniqueIndices.count == indices.count else {
            throw ErasureCodingError.duplicateShardIndices
        }

        logger.debug("Reconstructing from \(shards.count) shards (target length: \(originalLength))")

        let erasureShards = shards.map { shard in
            ErasureCoding.Shard(data: shard.data, index: UInt32(shard.index))
        }

        do {
            let reconstructed = try ErasureCoding.reconstruct(
                shards: erasureShards,
                basicSize: pieceSize,
                originalCount: originalShardCount,
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
    public func reconstructSegments(
        shards: [(index: UInt16, data: Data)],
        segmentCount: Int
    ) throws -> [Data4104] {
        let totalDataSize = segmentCount * 4104

        let reconstructedData = try reconstruct(
            shards: shards,
            originalLength: totalDataSize
        )

        var segments: [Data4104] = []
        segments.reserveCapacity(segmentCount)

        for i in 0 ..< segmentCount {
            let start = i * 4104
            let end = min(start + 4104, reconstructedData.count)
            let segmentData = Data(reconstructedData[start ..< end])

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

    /// Calculate erasure root: hash(shard) || segmentsRoot, then binary Merkle root
    public func calculateErasureRoot(segmentsRoot: Data32, shards: [Data]) throws -> Data32 {
        guard shards.count == totalShardCount else {
            throw ErasureCodingError.invalidShardCount(
                expected: totalShardCount,
                provided: shards.count
            )
        }

        let encodedSegmentsRoot = try JamEncoder.encode(segmentsRoot)
        var nodes: [Data] = []
        nodes.reserveCapacity(shards.count)

        for shard in shards {
            let shardHash = shard.blake2b256hash()
            let encodedShardHash = try JamEncoder.encode(shardHash)
            let node = encodedShardHash + encodedSegmentsRoot
            nodes.append(node)
        }

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
    public func generateMerkleProof(
        shardIndex: UInt16,
        segmentsRoot: Data32,
        shards: [Data]
    ) throws -> [Either<Data, Data32>] {
        guard shardIndex < UInt16(shards.count) else {
            throw ErasureCodingError.invalidShardIndex
        }

        // Reconstruct the same nodes used to build the Merkle tree in calculateErasureRoot
        let encodedSegmentsRoot = try JamEncoder.encode(segmentsRoot)
        var nodes: [Data] = []
        nodes.reserveCapacity(shards.count)

        for shard in shards {
            let shardHash = shard.blake2b256hash()
            let encodedShardHash = try JamEncoder.encode(shardHash)
            let node = encodedShardHash + encodedSegmentsRoot
            nodes.append(node)
        }

        let proof = Merklization.trace(
            nodes,
            index: Int(shardIndex),
            hasher: Blake2b256.self
        )

        logger.debug("Generated Merkle proof for shard \(shardIndex) with \(proof.count) steps")

        return proof
    }

    /// Verify Merkle proof for a shard
    public func verifyMerkleProof(
        shardHash: Data32,
        shardIndex: UInt16,
        proof: [Either<Data, Data32>],
        erasureRoot: Data32,
        segmentsRoot: Data32
    ) -> Bool {
        do {
            // Reconstruct the leaf node
            let encodedSegmentsRoot = try JamEncoder.encode(segmentsRoot)
            let encodedShardHash = try JamEncoder.encode(shardHash)
            let leafNode = encodedShardHash + encodedSegmentsRoot

            // Build up the Merkle root by combining with proof elements
            // The trace returns the result of binaryMerklizeHelper on the "other" partition
            var currentValue: Either<Data, Data32> = .left(leafNode)

            for (level, proofElement) in proof.enumerated() {
                // Extract the values to combine
                let currentValueData: Data
                let proofValueData: Data

                switch currentValue {
                case let .left(data):
                    currentValueData = data
                case let .right(hash):
                    currentValueData = hash.data
                }

                switch proofElement {
                case let .left(data):
                    proofValueData = data
                case let .right(hash):
                    proofValueData = hash.data
                }

                // Determine if current node is left or right child using shardIndex bits
                // Bit at position `level` tells us: 0 = left child, 1 = right child
                let isRightChild = (shardIndex >> level) & 1 == 1

                // Combine using binaryMerklizeHelper logic
                // If we're the right child, hash (sibling, current)
                // If we're the left child, hash (current, sibling)
                let combined: Data32 = if isRightChild {
                    Blake2b256.hash("node", proofValueData, currentValueData)
                } else {
                    Blake2b256.hash("node", currentValueData, proofValueData)
                }

                currentValue = .right(combined)
            }

            // After processing all proof elements, we should have .right(hash)
            // Use the hash directly (no extra hashing needed after combination)
            let result: Data32 = switch currentValue {
            case let .left(data):
                // This shouldn't happen if proof is correct, but handle it
                Blake2b256.hash(data)
            case let .right(hash):
                hash
            }

            let isValid = result == erasureRoot

            if isValid {
                logger.trace("Merkle proof verified for shard \(shardIndex)")
            } else {
                logger.warning("Merkle proof verification failed for shard \(shardIndex)")
            }

            return isValid
        } catch {
            logger.error("Failed to encode data for Merkle proof verification: \(error)")
            return false
        }
    }

    // MARK: - JAMNP-S Justification Generation

    /// Generate JAMNP-S justification for CE 137: co-path T(s, i, H)
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

        let encodedSegmentsRoot = try JamEncoder.encode(segmentsRoot)
        var nodes: [Data] = []
        nodes.reserveCapacity(shards.count)

        for shard in shards {
            let shardHash = shard.blake2b256hash()
            let encodedShardHash = try JamEncoder.encode(shardHash)
            let node = encodedShardHash + encodedSegmentsRoot
            nodes.append(node)
        }

        let copath = Merklization.trace(
            nodes,
            index: Int(shardIndex),
            hasher: Blake2b256.self
        )

        var steps: [AvailabilityJustification.AvailabilityJustificationStep] = []

        for step in copath {
            switch step {
            case let .left(data):
                // Determine if this is an internal node (already hashed) or leaf node (needs hashing)
                // Internal nodes from merkle tree are always 32 bytes (Blake2b256 output)
                // Leaf nodes contain concatenated data: encodedShardHash[32] + encodedSegmentsRoot[32] = 64 bytes
                // Segment shards are variable size (~12 bytes depending on encoding)
                let hash: Data32
                if data.count == 32 {
                    // Internal node - already a 32-byte hash from merkle tree
                    guard let h = Data32(data) else {
                        throw ErasureCodingError.invalidHash
                    }
                    hash = h
                } else {
                    // Leaf node (64 bytes) or segment shard (variable size) - hash to normalize
                    // This ensures all data is converted to 32-byte hashes for justification
                    hash = data.blake2b256hash()
                }
                steps.append(.left(hash))
            case let .right(hash):
                steps.append(.right(hash))
            }
        }

        logger.debug("Generated JAMNP-S justification for shard \(shardIndex) with \(steps.count) steps")

        return steps
    }

    /// Generate JAMNP-S justification for CE 140: j ++ [b] ++ T(s, i, H)
    public func generateSegmentJustification(
        segmentIndex: UInt16,
        bundleShardHash: Data32,
        shardIndex: UInt16,
        segmentsRoot _: Data32,
        shards: [Data],
        baseJustification: [AvailabilityJustification.AvailabilityJustificationStep]
    ) throws -> [AvailabilityJustification.AvailabilityJustificationStep] {
        guard Int(shardIndex) < shards.count else {
            throw ErasureCodingError.invalidShardIndex
        }

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

        let segmentCopath = Merklization.trace(
            segmentShards,
            index: Int(shardIndex),
            hasher: Blake2b256.self
        )

        var fullJustification = baseJustification

        fullJustification.append(.right(bundleShardHash))

        for step in segmentCopath {
            switch step {
            case let .left(data):
                // IMPORTANT: We rely on data size to distinguish node types
                // - Leaf nodes (segment shards): Variable size (~12 bytes each)
                // - Internal nodes: 32 bytes (hashes produced by Blake2b256)
                //
                // This assumption holds because:
                // 1. Segment shard nodes are constructed from variable-size data
                // 2. Merkle tree hashing always produces 32-byte outputs
                // 3. If tree structure changes, this logic must be updated
                let hash: Data32
                if data.count == 32 {
                    // Internal node - already a hash
                    guard let h = Data32(data) else {
                        throw ErasureCodingError.invalidHash
                    }
                    hash = h
                } else {
                    // Leaf node or non-standard size - hash it to normalize
                    // Note: Leaf nodes are 64 bytes (encodedShardHash + encodedSegmentsRoot)
                    // or variable size for segment shards (~12 bytes)
                    hash = data.blake2b256hash()
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
