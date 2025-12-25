import Codec
import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "ShardDistributionProtocol")

// GP spec constants from definitions.tex
private let cValCount: UInt16 = 1023 /// Total number of validators (Cvalcount)
private let cEcPiecesize = 684 /// Erasure coding piece size in octets
private let cEcOriginalCount = 342 /// Original shard count for reconstruction
private let cEcRecoveryCount = 1023 /// Recovery shard count

/// Protocol handlers for JAMNP-S CE 137-148 shard distribution protocols
///
/// Implements the server-side handling of shard distribution requests as per
/// the JAM Simple Networking Protocol specification.
public actor ShardDistributionProtocolHandlers {
    private let dataStore: ErasureCodingDataStore
    private let erasureCoding: ErasureCodingService
    private let config: ProtocolConfigRef

    public init(
        dataStore: ErasureCodingDataStore,
        erasureCoding: ErasureCodingService,
        config: ProtocolConfigRef
    ) {
        self.dataStore = dataStore
        self.erasureCoding = erasureCoding
        self.config = config
    }

    // MARK: - CE 137: Shard Distribution

    /// Handle CE 137: Shard distribution request
    ///
    /// Protocol flow:
    /// --> Erasure-Root ++ Shard Index
    /// --> FIN
    /// <-- Bundle Shard
    /// <-- [Segment Shard] (all exported + proof segments)
    /// <-- Justification (co-path T(s, i, H))
    /// <-- FIN
    ///
    /// - Parameter message: Shard distribution message
    /// - Returns: Encoded response containing bundle shard, segment shards, and justification
    public func handleShardDistribution(
        message: ShardDistributionMessage
    ) async throws -> [Data] {
        logger.debug(
            """
            CE 137: Shard distribution request for erasureRoot=\(message.erasureRoot.hex), \
            shardIndex=\(message.shardIndex)
            """
        )

        // Check if we have this erasure root
        let hasShard = try await dataStore.hasShard(
            erasureRoot: message.erasureRoot,
            shardIndex: message.shardIndex
        )

        guard hasShard else {
            logger.warning(
                """
                CE 137: Shard \(message.shardIndex) for erasureRoot \(message.erasureRoot.hex) not found
                """
            )
            throw ShardDistributionError.shardNotFound
        }

        // Retrieve the shard
        let shardData = try await dataStore.getShard(
            erasureRoot: message.erasureRoot,
            shardIndex: message.shardIndex
        )

        guard let shardData else {
            logger.warning("CE 137: Shard data is nil for index \(message.shardIndex)")
            throw ShardDistributionError.shardDataUnavailable
        }

        // Get metadata
        let metadata = try await dataStore.getAuditEntry(erasureRoot: message.erasureRoot)
        guard let metadata else {
            logger.warning("CE 137: No metadata found for erasureRoot \(message.erasureRoot.hex)")
            throw ShardDistributionError.metadataNotFound
        }

        // Extract bundle shard and segment shards from the shard data
        // Per spec, shard contains: [bundle shard (684 bytes)] + [segment shards for each segment]
        let bundleShardSize = 684
        let segmentCount = metadata.segmentCount

        guard shardData.count >= bundleShardSize else {
            logger.error("CE 137: Shard data too small: \(shardData.count) bytes")
            throw ShardDistributionError.invalidShardData
        }

        // Extract bundle shard (first 684 bytes)
        let bundleShard = Data(shardData[0 ..< bundleShardSize])

        // Extract segment shards (remaining data divided by segment count)
        let segmentShardSize = (shardData.count - bundleShardSize) / Int(segmentCount)
        var segmentShards: [Data] = []

        for i in 0 ..< Int(segmentCount) {
            let start = bundleShardSize + (i * segmentShardSize)
            let end = min(start + segmentShardSize, shardData.count)
            let segmentShard = Data(shardData[start ..< end])
            segmentShards.append(segmentShard)
        }

        // Generate justification T(s, i, H)
        // s = sequence of (bundle shard hash, segment shard root) pairs
        // We need all shard hashes to generate the justification

        // Get all shard hashes for this erasure root
        let allShardHashes = try await getAllShardHashes(erasureRoot: message.erasureRoot)

        // Generate the Merkle co-path for the requested shard
        let justification = try erasureCoding.generateJustification(
            shardIndex: message.shardIndex,
            segmentsRoot: metadata.segmentsRoot,
            shards: allShardHashes.map { Data($0) }
        )

        logger.debug(
            """
            CE 137: Returning bundle shard + \(segmentShards.count) segment shards + \
            justification with \(justification.count) steps
            """
        )

        // Encode response: Bundle Shard ++ [Segment Shard] ++ Justification
        let encoder = JamEncoder()

        // Encode bundle shard (length-prefixed)
        try encoder.encode(bundleShard)

        // Encode segment shards (length-prefixed array)
        try encoder.encode(UInt32(segmentShards.count))
        for segmentShard in segmentShards {
            try encoder.encode(segmentShard)
        }

        // Encode justification
        try encodeJustification(encoder, justification: justification)

        return [encoder.data]
    }

    // MARK: - CE 138: Audit Shard Request

    /// Handle CE 138: Audit shard request
    ///
    /// Protocol flow:
    /// --> Erasure-Root ++ Shard Index
    /// --> FIN
    /// <-- Bundle Shard
    /// <-- Justification
    /// <-- FIN
    ///
    /// - Parameter message: Audit shard request message
    /// - Returns: Encoded response containing bundle shard and justification
    public func handleAuditShardRequest(
        message: AuditShardRequestMessage
    ) async throws -> [Data] {
        logger.debug(
            """
            CE 138: Audit shard request for erasureRoot=\(message.erasureRoot.hex), \
            shardIndex=\(message.shardIndex)
            """
        )

        // Reuse CE 137 logic but only return bundle shard + justification
        let shardDistributionMsg = ShardDistributionMessage(
            erasureRoot: message.erasureRoot,
            shardIndex: message.shardIndex
        )

        let fullResponse = try await handleShardDistribution(message: shardDistributionMsg)

        // Decode the full response to extract just bundle shard + justification
        let decoder = JamDecoder(data: fullResponse[0], config: config)

        // Decode bundle shard
        let bundleShard = try decoder.decode(Data.self)

        // Skip segment shards array
        let segmentShardCount = try decoder.decode(UInt32.self)
        for _ in 0 ..< segmentShardCount {
            _ = try decoder.decode(Data.self)
        }

        // Decode justification (remainder of data)
        let justificationData = Data(decoder.remainingData)

        logger.debug(
            """
            CE 138: Returning bundle shard + justification for shard \(message.shardIndex)
            """
        )

        // Re-encode just bundle shard + justification
        let encoder = JamEncoder()
        try encoder.encode(bundleShard)
        encoder.data.append(justificationData)

        return [encoder.data]
    }

    // MARK: - CE 139/140: Segment Shard Request

    /// Handle CE 139: Segment shard request (fast mode, no justification)
    ///
    /// Protocol flow:
    /// --> [Erasure-Root ++ Shard Index ++ len++[Segment Index]]
    /// --> FIN
    /// <-- [Segment Shard]
    /// <-- FIN
    ///
    /// - Parameter message: Segment shard request message
    /// - Returns: Encoded response containing segment shards
    public func handleSegmentShardRequestFast(
        message: SegmentShardRequestMessage
    ) async throws -> [Data] {
        logger.debug(
            """
            CE 139: Fast segment shard request for erasureRoot=\(message.erasureRoot.hex), \
            shardIndex=\(message.shardIndex), segmentIndices=\(message.segmentIndices.count)
            """
        )

        let shardData = try await getShardData(
            erasureRoot: message.erasureRoot,
            shardIndex: message.shardIndex
        )

        let metadata = try await getAuditMetadata(erasureRoot: message.erasureRoot)

        // Extract segment shards for requested indices
        let segmentShards = try extractSegmentShards(
            from: shardData,
            segmentIndices: message.segmentIndices,
            segmentCount: metadata.segmentCount
        )

        logger.debug("CE 139: Returning \(segmentShards.count) segment shards (fast mode)")

        // Encode response: [Segment Shard] (length-prefixed array)
        let encoder = JamEncoder()
        try encoder.encode(UInt32(segmentShards.count))
        for segmentShard in segmentShards {
            try encoder.encode(segmentShard)
        }

        return [encoder.data]
    }

    /// Handle CE 140: Segment shard request (verified mode, with justification)
    ///
    /// Protocol flow:
    /// --> [Erasure-Root ++ Shard Index ++ len++[Segment Index]]
    /// --> FIN
    /// <-- [Segment Shard]
    /// for each segment shard {
    ///     <-- Justification
    /// }
    /// <-- FIN
    ///
    /// - Parameter message: Segment shard request message
    /// - Returns: Encoded response containing segment shards and justifications
    public func handleSegmentShardRequestVerified(
        message: SegmentShardRequestMessage
    ) async throws -> [Data] {
        logger.debug(
            """
            CE 140: Verified segment shard request for erasureRoot=\(message.erasureRoot.hex), \
            shardIndex=\(message.shardIndex), segmentIndices=\(message.segmentIndices.count)
            """
        )

        let shardData = try await getShardData(
            erasureRoot: message.erasureRoot,
            shardIndex: message.shardIndex
        )

        let metadata = try await getAuditMetadata(erasureRoot: message.erasureRoot)

        // Extract segment shards for requested indices
        let segmentShards = try extractSegmentShards(
            from: shardData,
            segmentIndices: message.segmentIndices,
            segmentCount: metadata.segmentCount
        )

        // Generate justifications for each segment shard
        var responses: [Data] = []

        // First response: [Segment Shard] array
        let encoder = JamEncoder()
        try encoder.encode(UInt32(segmentShards.count))
        for segmentShard in segmentShards {
            try encoder.encode(segmentShard)
        }
        responses.append(encoder.data)

        // For each segment shard, generate and append justification
        for (index, segmentIndex) in message.segmentIndices.enumerated() {
            let justification = try await generateSegmentJustification(
                erasureRoot: message.erasureRoot,
                shardIndex: message.shardIndex,
                segmentIndex: segmentIndex,
                bundleShard: extractBundleShard(from: shardData),
                segmentShard: segmentShards[index]
            )

            let justEncoder = JamEncoder()
            try encodeJustification(justEncoder, justification: justification)
            responses.append(justEncoder.data)
        }

        logger.debug(
            """
            CE 140: Returning \(segmentShards.count) segment shards + \(responses.count - 1) justifications
            """
        )

        return responses
    }

    // MARK: - CE 147: Bundle Request

    /// Handle CE 147: Bundle request
    ///
    /// Protocol flow:
    /// --> Erasure-Root
    /// --> FIN
    /// <-- Work-Package Bundle
    /// <-- FIN
    ///
    /// - Parameter message: Block request message (reusing for erasure root)
    /// - Returns: Encoded work-package bundle
    public func handleBundleRequest(
        erasureRoot: Data32
    ) async throws -> [Data] {
        logger.debug("CE 147: Bundle request for erasureRoot=\(erasureRoot.hex)")

        // Retrieve the full bundle from storage
        let metadata = try await dataStore.getAuditEntry(erasureRoot: erasureRoot)

        guard let metadata else {
            logger.warning("CE 147: No metadata found for erasureRoot \(erasureRoot.hex)")
            throw ShardDistributionError.metadataNotFound
        }

        // Reconstruct the bundle from shards
        let shardAssignments = JAMNPSShardAssignment()
        let validators = shardAssignments.getValidatorsForShard(
            shardIndex: 0, // Will need all shards for full bundle
            coreIndex: 0,
            totalValidators: cValCount
        )

        // Collect available shards
        var collectedShards: [(UInt16, Data)] = []
        for validatorIndex in validators {
            if let shard = try await dataStore.getShard(
                erasureRoot: erasureRoot,
                shardIndex: validatorIndex
            ) {
                collectedShards.append((validatorIndex, shard))
            }
        }

        guard collectedShards.count >= 342 else {
            logger.warning(
                """
                CE 147: Insufficient shards for reconstruction: \
                \(collectedShards.count)/342
                """
            )
            throw ShardDistributionError.insufficientShards
        }

        // Reconstruct the bundle
        let bundleData = try await erasureCoding.reconstruct(
            shards: collectedShards,
            originalLength: Int(metadata.bundleSize)
        )

        logger.debug("CE 147: Returning bundle of \(bundleData.count) bytes")

        return [bundleData]
    }

    // MARK: - CE 148: Segment Request

    /// Handle CE 148: Segment request
    ///
    /// Protocol flow:
    /// --> Segments-Root ++ len++[Segment Index]
    /// --> FIN
    /// <-- [Segment]
    /// <-- FIN
    ///
    /// - Parameter segmentsRoot: The segments root
    /// - Parameter segmentIndices: Array of segment indices to fetch
    /// - Returns: Encoded segments
    public func handleSegmentRequest(
        segmentsRoot: Data32,
        segmentIndices: [UInt16]
    ) async throws -> [Data] {
        logger.debug(
            """
            CE 148: Segment request for segmentsRoot=\(segmentsRoot.hex), \
            indices=\(segmentIndices.count)
            """
        )

        var segments: [Data] = []

        for segmentIndex in segmentIndices {
            // Look up segment by root and index
            // Note: This requires a segmentsRoot -> erasureRoot mapping
            // For now, we'll need to iterate through D³L entries

            let segment = try await getSegmentByRootAndIndex(
                segmentsRoot: segmentsRoot,
                segmentIndex: segmentIndex
            )

            segments.append(segment)
        }

        logger.debug("CE 148: Returning \(segments.count) segments")

        // Encode response: [Segment] (length-prefixed array)
        let encoder = JamEncoder()
        try encoder.encode(UInt32(segments.count))
        for segment in segments {
            try encoder.encode(segment)
        }

        return [encoder.data]
    }

    // MARK: - Helper Methods

    private func getShardData(
        erasureRoot: Data32,
        shardIndex: UInt16
    ) async throws -> Data {
        let hasShard = try await dataStore.hasShard(
            erasureRoot: erasureRoot,
            shardIndex: shardIndex
        )

        guard hasShard else {
            throw ShardDistributionError.shardNotFound
        }

        let shardData = try await dataStore.getShard(
            erasureRoot: erasureRoot,
            shardIndex: shardIndex
        )

        guard let shardData else {
            throw ShardDistributionError.shardDataUnavailable
        }

        return shardData
    }

    private func getAuditMetadata(erasureRoot: Data32) async throws -> AuditEntry {
        let metadata = try await dataStore.getAuditEntry(erasureRoot: erasureRoot)

        guard let metadata else {
            throw ShardDistributionError.metadataNotFound
        }

        return metadata
    }

    private func getAllShardHashes(erasureRoot: Data32) async throws -> [Data32] {
        // Get metadata to determine shard count
        let metadata = try await getAuditMetadata(erasureRoot: erasureRoot)

        var hashes: [Data32] = []
        for i in 0 ..< cEcRecoveryCount {
            if let shardData = try await dataStore.getShard(
                erasureRoot: erasureRoot,
                shardIndex: UInt16(i)
            ) {
                hashes.append(shardData.blake2b256hash())
            }
        }

        return hashes
    }

    private func extractSegmentShards(
        from shardData: Data,
        segmentIndices: [UInt16],
        segmentCount: UInt32
    ) throws -> [Data] {
        let bundleShardSize = 684
        let totalSegmentDataSize = shardData.count - bundleShardSize
        let segmentShardSize = totalSegmentDataSize / Int(segmentCount)

        var segmentShards: [Data] = []

        for segmentIndex in segmentIndices {
            let offset = bundleShardSize + (Int(segmentIndex) * segmentShardSize)
            let endOffset = min(offset + segmentShardSize, shardData.count)

            guard offset < shardData.count else {
                logger.warning("Segment index \(segmentIndex) out of bounds")
                continue
            }

            let segmentShard = Data(shardData[offset ..< endOffset])
            segmentShards.append(segmentShard)
        }

        return segmentShards
    }

    private func extractBundleShard(from shardData: Data) -> Data {
        let bundleShardSize = 684
        return Data(shardData[0 ..< bundleShardSize])
    }

    private func generateSegmentJustification(
        erasureRoot: Data32,
        shardIndex: UInt16,
        segmentIndex: UInt16,
        bundleShard _: Data,
        segmentShard _: Data
    ) async throws -> [Justification.JustificationStep] {
        // CE 140 requires a justification that proves the segment shard belongs to the segment
        //
        // Per GP spec, we need to generate a Merkle co-path that proves:
        // 1. The segment shard is part of the shard
        // 2. The shard is part of the erasure-coded data
        //
        // Strategy:
        // - Calculate all segment shard hashes within this shard
        // - Generate Merkle tree from these segment shard hashes
        // - Provide co-path for the requested segment

        // Get metadata to determine segment count
        let metadata = try await getAuditMetadata(erasureRoot: erasureRoot)
        let segmentCount = Int(metadata.segmentCount)

        // Extract all segment shards from this shard
        let shardData = try await getShardData(
            erasureRoot: erasureRoot,
            shardIndex: shardIndex
        )

        let segmentShards = try extractSegmentShards(
            from: shardData,
            segmentIndices: Array(0 ..< UInt16(segmentCount)),
            segmentCount: metadata.segmentCount
        )

        // Generate Merkle tree nodes for segment shards
        // Node format: encode(segmentShardHash) || encode(segmentIndex)
        var nodes: [Data] = []
        for (idx, segShard) in segmentShards.enumerated() {
            let segmentShardHash = segShard.blake2b256hash()
            let segmentIndexData = JamEncoder.encode(UInt32(idx))

            var nodeData = Data()
            nodeData.append(segmentShardHash)
            nodeData.append(contentsOf: segmentIndexData)
            nodes.append(nodeData)
        }

        // Generate co-path using Merkle trace
        let copath = Merklization.trace(
            nodes,
            index: Int(segmentIndex),
            hasher: Blake2b256.self
        )

        // Convert copath to justification steps
        return copath.map { nodeHash in
            .right(Data32(nodeHash))
        }
    }

    private func getSegmentByRootAndIndex(
        segmentsRoot: Data32,
        segmentIndex: UInt16
    ) async throws -> Data {
        // Look up D³L entry by segments root
        let d3lEntry = try await dataStore.getD3LEntry(segmentsRoot: segmentsRoot)

        guard let d3lEntry else {
            logger.warning(
                """
                CE 148: No D³L entry found for segmentsRoot \(segmentsRoot.hex), \
                segment \(segmentIndex)
                """
            )
            throw ShardDistributionError.segmentNotFound
        }

        // Retrieve the segment data
        let segmentData = try await dataStore.getSegment(
            erasureRoot: d3lEntry.erasureRoot,
            segmentIndex: segmentIndex
        )

        guard let segmentData else {
            throw ShardDistributionError.segmentDataUnavailable
        }

        return segmentData
    }

    private func encodeJustification(
        _ encoder: JamEncoder,
        justification: [Justification.JustificationStep]
    ) throws {
        // Encode justification steps
        // Format: [discriminator ++ hash] per step
        // discriminator: 0 = left, 1 = right

        for step in justification {
            switch step {
            case let .left(hash):
                try encoder.encode(UInt8(0))
                try encoder.encode(hash)
            case let .right(hash):
                try encoder.encode(UInt8(1))
                try encoder.encode(hash)
            }
        }
    }
}

// MARK: - Errors

public enum ShardDistributionError: Error {
    case shardNotFound
    case shardDataUnavailable
    case invalidShardData
    case metadataNotFound
    case insufficientShards
    case segmentNotFound
    case segmentDataUnavailable
}
