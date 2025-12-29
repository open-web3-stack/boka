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

/// Cache for shard hashes
private actor ShardHashCache {
    private var cache: [Data32: [Data32]] = [:]
    private var accessTimes: [Data32: Date] = [:]

    func get(_ key: Data32) -> [Data32]? {
        accessTimes[key] = Date()
        return cache[key]
    }

    func set(_ key: Data32, hashes: [Data32]) {
        cache[key] = hashes
        accessTimes[key] = Date()

        if cache.count > 1000 {
            evictOldest()
        }
    }

    private func evictOldest() {
        guard let oldestKey = accessTimes.min(by: { $0.value < $1.value })?.key else {
            return
        }
        cache.removeValue(forKey: oldestKey)
        accessTimes.removeValue(forKey: oldestKey)
        logger.debug("Evicted oldest shard hash cache entry")
    }
}

/// JAMNP-S CE 137-148 shard distribution protocol handlers
public actor ShardDistributionProtocolHandlers {
    private let dataStore: ErasureCodingDataStore
    private let erasureCoding: ErasureCodingService
    private let config: ProtocolConfigRef
    private let shardHashCache = ShardHashCache()

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
    public func handleShardDistribution(
        message: some ShardDistributionRequestProtocol
    ) async throws -> [Data] {
        logger.debug(
            """
            CE 137: Shard distribution request for erasureRoot=\(message.erasureRoot.toHexString()), \
            shardIndex=\(message.shardIndex)
            """
        )

        let hasShard = try await dataStore.hasShard(
            erasureRoot: message.erasureRoot,
            shardIndex: message.shardIndex
        )

        guard hasShard else {
            logger.warning(
                """
                CE 137: Shard \(message.shardIndex) for erasureRoot \(message.erasureRoot.toHexString()) not found
                """
            )
            throw ShardDistributionError.shardNotFound
        }

        let shardData = try await dataStore.getShard(
            erasureRoot: message.erasureRoot,
            shardIndex: message.shardIndex
        )

        guard let shardData else {
            logger.warning("CE 137: Shard data is nil for index \(message.shardIndex)")
            throw ShardDistributionError.shardDataUnavailable
        }

        // Fetch metadata in parallel
        let erasureRoot = message.erasureRoot
        async let auditMetadata = dataStore.getAuditEntry(erasureRoot: erasureRoot)
        async let d3lMetadata = dataStore.getD3LEntry(erasureRoot: erasureRoot)

        guard let _ = try await auditMetadata else {
            logger.warning("CE 137: No audit metadata found for erasureRoot \(erasureRoot.toHexString())")
            throw ShardDistributionError.metadataNotFound
        }

        guard let d3lMetadata = try await d3lMetadata else {
            logger.warning("CE 137: No D³L metadata found for erasureRoot \(erasureRoot.toHexString())")
            throw ShardDistributionError.metadataNotFound
        }

        // Extract bundle shard and segment shards
        let bundleShardSize = 684
        let segmentCount = Int(d3lMetadata.segmentCount)

        guard shardData.count >= bundleShardSize else {
            logger.error("CE 137: Shard data too small: \(shardData.count) bytes")
            throw ShardDistributionError.invalidShardData
        }

        let bundleShard = Data(shardData[0 ..< bundleShardSize])

        let segmentShardSize = (shardData.count - bundleShardSize) / Int(segmentCount)
        var segmentShards: [Data] = []

        for i in 0 ..< Int(segmentCount) {
            let start = bundleShardSize + (i * segmentShardSize)
            let end = min(start + segmentShardSize, shardData.count)
            let segmentShard = Data(shardData[start ..< end])
            segmentShards.append(segmentShard)
        }

        // Generate justification
        let allShardHashes = try await getAllShardHashes(erasureRoot: message.erasureRoot)

        let justification = try await erasureCoding.generateJustification(
            shardIndex: message.shardIndex,
            segmentsRoot: d3lMetadata.segmentsRoot,
            shards: allShardHashes.map(\.data)
        )

        logger.debug(
            """
            CE 137: Returning bundle shard + \(segmentShards.count) segment shards + \
            justification with \(justification.count) steps
            """
        )

        let encoder = JamEncoder()

        try encoder.encode(bundleShard)

        try encoder.encode(UInt32(segmentShards.count))
        for segmentShard in segmentShards {
            try encoder.encode(segmentShard)
        }

        try encoder.encode(UInt32(justification.count))
        try encodeJustification(encoder, justification: justification)

        return [encoder.data]
    }

    // MARK: - CE 138: Audit Shard Request

    /// Handle CE 138: Audit shard request
    public func handleAuditShardRequest(
        message: some AuditShardRequestProtocol
    ) async throws -> [Data] {
        logger.debug(
            """
            CE 138: Audit shard request for erasureRoot=\(message.erasureRoot.toHexString()), \
            shardIndex=\(message.shardIndex)
            """
        )

        let shardDistributionMsg = SimpleShardDistributionRequest(
            erasureRoot: message.erasureRoot,
            shardIndex: message.shardIndex
        )

        let fullResponse = try await handleShardDistribution(message: shardDistributionMsg)

        var decoder = try JamDecoder(data: fullResponse[0], config: config)

        let bundleShard = try decoder.decode(Data.self)

        let segmentShardCount = try decoder.decode(UInt32.self)
        for _ in 0 ..< segmentShardCount {
            _ = try decoder.decode(Data.self)
        }

        let justificationSteps = try decoder.decode([AvailabilityJustification.AvailabilityJustificationStep].self)

        logger.debug(
            """
            CE 138: Returning bundle shard + justification for shard \(message.shardIndex)
            """
        )

        let encoder = JamEncoder()
        try encoder.encode(bundleShard)
        try encoder.encode(justificationSteps)

        return [encoder.data]
    }

    // MARK: - CE 139/140: Segment Shard Request

    /// Handle CE 139: Segment shard request (fast mode)
    public func handleSegmentShardRequestFast(
        message: some SegmentShardRequestProtocol
    ) async throws -> [Data] {
        logger.debug(
            """
            CE 139: Fast segment shard request for erasureRoot=\(message.erasureRoot.toHexString()), \
            shardIndex=\(message.shardIndex), segmentIndices=\(message.segmentIndices.count)
            """
        )

        let shardData = try await getShardData(
            erasureRoot: message.erasureRoot,
            shardIndex: message.shardIndex
        )

        // Get D³L metadata for segment count
        let d3lMetadata = try await getD3LMetadata(erasureRoot: message.erasureRoot)

        // Extract segment shards for requested indices
        let segmentShards = try extractSegmentShards(
            from: shardData,
            segmentIndices: message.segmentIndices,
            segmentCount: d3lMetadata.segmentCount
        )

        logger.debug("CE 139: Returning \(segmentShards.count) segment shards (fast mode)")

        let encoder = JamEncoder()
        try encoder.encode(UInt32(segmentShards.count))
        for segmentShard in segmentShards {
            try encoder.encode(segmentShard)
        }

        return [encoder.data]
    }

    /// Handle CE 140: Segment shard request (verified mode)
    public func handleSegmentShardRequestVerified(
        message: some SegmentShardRequestProtocol
    ) async throws -> [Data] {
        logger.debug(
            """
            CE 140: Verified segment shard request for erasureRoot=\(message.erasureRoot.toHexString()), \
            shardIndex=\(message.shardIndex), segmentIndices=\(message.segmentIndices.count)
            """
        )

        let shardData = try await getShardData(
            erasureRoot: message.erasureRoot,
            shardIndex: message.shardIndex
        )

        // Get D³L metadata for segment count
        let d3lMetadata = try await getD3LMetadata(erasureRoot: message.erasureRoot)

        // Extract segment shards for requested indices
        let segmentShards = try extractSegmentShards(
            from: shardData,
            segmentIndices: message.segmentIndices,
            segmentCount: d3lMetadata.segmentCount
        )

        // Extract bundle shard
        let bundleShard = extractBundleShard(from: shardData)

        // Generate all justifications
        var allJustifications: [[AvailabilityJustification.AvailabilityJustificationStep]] = []
        for (index, segmentIndex) in message.segmentIndices.enumerated() {
            let justification = try await generateSegmentJustification(
                erasureRoot: message.erasureRoot,
                shardIndex: message.shardIndex,
                segmentIndex: segmentIndex,
                bundleShard: bundleShard,
                segmentShard: segmentShards[index]
            )
            allJustifications.append(justification)
        }

        // Create single ShardResponse with all data
        let encoder = JamEncoder()
        try encoder.encode(bundleShard)
        try encoder.encode(UInt32(segmentShards.count))
        for segmentShard in segmentShards {
            try encoder.encode(segmentShard)
        }

        // Encode justifications count
        try encoder.encode(UInt32(allJustifications.count))
        for justification in allJustifications {
            try encodeJustification(encoder, justification: justification)
        }

        logger.debug(
            """
            CE 140: Returning ShardResponse with bundle shard + \(segmentShards.count) segment shards + \(allJustifications
                .count) justifications
            """
        )

        return [encoder.data]
    }

    // MARK: - CE 147: Bundle Request

    /// Handle CE 147: Bundle request
    public func handleBundleRequest(
        erasureRoot: Data32
    ) async throws -> [Data] {
        logger.debug("CE 147: Bundle request for erasureRoot=\(erasureRoot.toHexString())")

        let metadata = try await dataStore.getAuditEntry(erasureRoot: erasureRoot)

        guard let metadata else {
            logger.warning("CE 147: No metadata found for erasureRoot \(erasureRoot.toHexString())")
            throw ShardDistributionError.metadataNotFound
        }

        let shardAssignments = JAMNPSShardAssignment()
        let validators = await shardAssignments.getValidatorsForShard(
            shardIndex: 0, // Will need all shards for full bundle
            coreIndex: 0,
            totalValidators: cValCount
        )

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

        let bundleData = try await erasureCoding.reconstruct(
            shards: collectedShards,
            originalLength: Int(metadata.bundleSize)
        )

        logger.debug("CE 147: Returning bundle of \(bundleData.count) bytes")

        // Wrap in BundleResponse as expected by the client
        let encoder = JamEncoder()
        try encoder.encode(bundleData)

        return [encoder.data]
    }

    // MARK: - CE 148: Segment Request

    /// Handle CE 148: Segment request
    public func handleSegmentRequest(
        segmentsRoot: Data32,
        segmentIndices: [UInt16]
    ) async throws -> [Data] {
        logger.debug(
            """
            CE 148: Segment request for segmentsRoot=\(segmentsRoot.toHexString()), \
            indices=\(segmentIndices.count)
            """
        )

        var segments: [Data] = []

        for segmentIndex in segmentIndices {
            let segment = try await getSegmentByRootAndIndex(
                segmentsRoot: segmentsRoot,
                segmentIndex: segmentIndex
            )

            segments.append(segment)
        }

        logger.debug("CE 148: Returning \(segments.count) segments")

        // Format as SegmentResponse: segments count + segments + import proofs count (0 for now)
        let encoder = JamEncoder()
        try encoder.encode(UInt32(segments.count))
        for segment in segments {
            try encoder.encode(segment)
        }

        // Import proofs not currently tracked - send empty array
        try encoder.encode(UInt32(0))

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

    private func getD3LMetadata(erasureRoot: Data32) async throws -> D3LEntry {
        let metadata = try await dataStore.getD3LEntry(erasureRoot: erasureRoot)

        guard let metadata else {
            throw ShardDistributionError.metadataNotFound
        }

        return metadata
    }

    private func getAllShardHashes(erasureRoot: Data32) async throws -> [Data32] {
        if let cachedHashes = await shardHashCache.get(erasureRoot) {
            logger.debug("Cache hit for shard hashes: erasureRoot=\(erasureRoot.toHexString())")
            return cachedHashes
        }

        logger.debug("Cache miss for shard hashes, computing: erasureRoot=\(erasureRoot.toHexString())")

        let allShardIndices = Array(0 ..< UInt16(cEcRecoveryCount))
        let shards = try await dataStore.getShards(erasureRoot: erasureRoot, shardIndices: allShardIndices)

        var hashes: [Data32] = []
        hashes.reserveCapacity(cEcRecoveryCount)

        for shard in shards {
            hashes.append(shard.data.blake2b256hash())
        }

        await shardHashCache.set(erasureRoot, hashes: hashes)

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
        segmentShards.reserveCapacity(segmentIndices.count)

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
    ) async throws -> [AvailabilityJustification.AvailabilityJustificationStep] {
        let d3lMetadata = try await getD3LMetadata(erasureRoot: erasureRoot)
        let segmentCount = Int(d3lMetadata.segmentCount)

        let shardData = try await getShardData(
            erasureRoot: erasureRoot,
            shardIndex: shardIndex
        )

        let segmentShards = try extractSegmentShards(
            from: shardData,
            segmentIndices: Array(0 ..< UInt16(segmentCount)),
            segmentCount: UInt32(segmentCount)
        )

        var nodes: [Data] = []
        for (idx, segShard) in segmentShards.enumerated() {
            let segmentShardHash = segShard.blake2b256hash()
            let segmentIndexData = try JamEncoder.encode(UInt32(idx))

            var nodeData = Data()
            nodeData.append(segmentShardHash.data)
            nodeData.append(contentsOf: segmentIndexData)
            nodes.append(nodeData)
        }

        let copath = Merklization.trace(
            nodes,
            index: Int(segmentIndex),
            hasher: Blake2b256.self
        )

        return copath.map { either in
            switch either {
            case let .left(data):
                .right(data.blake2b256hash())
            case let .right(hash):
                .right(hash)
            }
        }
    }

    private func getSegmentByRootAndIndex(
        segmentsRoot: Data32,
        segmentIndex: UInt16
    ) async throws -> Data {
        let d3lEntry = try await dataStore.getD3LEntry(segmentsRoot: segmentsRoot)

        guard let d3lEntry else {
            logger.warning(
                """
                CE 148: No D³L entry found for segmentsRoot \(segmentsRoot.toHexString()), \
                segment \(segmentIndex)
                """
            )
            throw ShardDistributionError.segmentNotFound
        }

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
        justification: [AvailabilityJustification.AvailabilityJustificationStep]
    ) throws {
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
