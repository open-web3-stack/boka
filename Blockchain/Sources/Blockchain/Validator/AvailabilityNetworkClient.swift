import Foundation
import Networking
import TracingUtils
import Utils

private let logger = Logger(label: "AvailabilityNetworkClient")

/// Network protocol for sending requests (local abstraction to avoid Node dependency)
public protocol AvailabilityNetworkProtocol: Sendable {
    func send(to: NetAddr, data: Data) async throws -> [Data]
}

/// Network client for fetching availability shards via JAMNP-S protocols
///
/// Implements JAMNP-S CE 137/138/139/140/147/148 for shard distribution.
public actor AvailabilityNetworkClient {
    private let config: ProtocolConfigRef
    private let erasureCoding: ErasureCodingService
    private let shardAssignment: JAMNPSShardAssignment

    /// Network protocol for sending requests
    private var network: (any AvailabilityNetworkProtocol)?

    /// Request timeout in seconds
    private let requestTimeout: TimeInterval = 30.0

    /// Maximum concurrent requests
    private let maxConcurrentRequests: Int = 50

    /// Request sending helpers for deduplication and timeout handling
    private let requestHelpers = RequestSendingHelpers()

    /// Fallback timeout configuration
    private var fallbackTimeoutConfig = FallbackTimeoutConfig()

    public init(
        config: ProtocolConfigRef,
        erasureCoding: ErasureCodingService
    ) {
        self.config = config
        self.erasureCoding = erasureCoding
        shardAssignment = JAMNPSShardAssignment()
    }

    /// Set the network protocol for sending requests
    public func setNetwork(_ network: any AvailabilityNetworkProtocol) {
        self.network = network
    }

    /// Get the network protocol (exposed for DataAvailabilityService to use)
    public func getNetwork() -> (any AvailabilityNetworkProtocol)? {
        network
    }

    /// Configure fallback timeouts
    /// - Parameter config: Fallback timeout configuration
    public func configureFallbackTimeouts(_ config: FallbackTimeoutConfig) {
        fallbackTimeoutConfig = config
        logger.info(
            """
            Fallback timeouts configured: local=\(config.localTimeout)s, \
            ce147=\(config.ce147Timeout)s, ce138=\(config.ce138Timeout)s, \
            ce139=\(config.ce139Timeout)s, ce140=\(config.ce140Timeout)s, \
            ce148=\(config.ce148Timeout)s
            """
        )
    }

    // MARK: - CE 138: Audit Shard Request

    /// Fetch a single audit shard from an assurer
    ///
    /// Implements JAMNP-S CE 138: Audit shard request.
    /// Delegates to CE138Handler for the actual implementation.
    ///
    /// - Parameters:
    ///   - erasureRoot: The erasure root
    ///   - shardIndex: The shard index to fetch
    ///   - assurerAddress: The assurer's network address
    /// - Returns: Tuple of (bundle shard, justification)
    /// - Throws: AvailabilityNetworkingError if request fails
    public func fetchAuditShard(
        erasureRoot: Data32,
        shardIndex: UInt16,
        from assurerAddress: NetAddr
    ) async throws -> (Data, AvailabilityJustification) {
        guard let network else {
            logger.error("Network not set - call setNetwork() first")
            throw AvailabilityNetworkingError.peerManagerUnavailable
        }

        logger.debug(
            """
            Fetching audit shard \(shardIndex) from \(assurerAddress)
            """
        )

        // Build request
        let requestData = try ShardRequest(
            erasureRoot: erasureRoot,
            shardIndex: shardIndex,
            segmentIndices: nil
        ).encode()

        // Use request helpers for deduplication and metrics
        let responseData = try await requestHelpers.sendRequest(
            to: assurerAddress,
            requestType: .auditShard,
            data: requestData,
            network: network
        )

        let response = try ShardResponse.decode(responseData)

        // Verify we got a bundle shard
        guard !response.bundleShard.isEmpty else {
            throw AvailabilityNetworkingError.decodingFailed
        }

        // AvailabilityJustification should be the co-path from erasure-root to the shard
        let justification = response.justification

        logger.info(
            """
            Successfully fetched audit shard \(shardIndex) from \(assurerAddress)
            """
        )

        return (response.bundleShard, justification)
    }

    // MARK: - CE 139/140: Segment Shard Request

    /// Fetch segment shards from an assurer (without justification - CE 139)
    ///
    /// Implements JAMNP-S CE 139: Segment shard request.
    /// Delegates to CESegmentShardHandler for the actual implementation.
    ///
    /// - Parameters:
    ///   - erasureRoot: The erasure root
    ///   - shardIndex: The shard index to fetch
    ///   - segmentIndices: Segment indices to fetch
    ///   - assurerAddress: The assurer's network address
    /// - Returns: Array of segment shards
    /// - Throws: AvailabilityNetworkingError if request fails
    public func fetchSegmentShards(
        erasureRoot: Data32,
        shardIndex: UInt16,
        segmentIndices: [UInt16],
        from assurerAddress: NetAddr
    ) async throws -> [Data] {
        // Delegate to CESegmentShardHandler
        guard let network else {
            logger.error("Network not set - call setNetwork() first")
            throw AvailabilityNetworkingError.peerManagerUnavailable
        }

        return try await CESegmentShardHandler.fetchSegmentShards(
            network: network,
            erasureRoot: erasureRoot,
            shardIndex: shardIndex,
            segmentIndices: segmentIndices,
            from: assurerAddress
        )
    }

    /// Fetch segment shards with justification (CE 140)
    ///
    /// Use this when verification is needed (e.g., after detecting inconsistency).
    ///
    /// Implements JAMNP-S CE 140: Segment shard request with justification.
    /// Delegates to CESegmentShardHandler for the actual implementation.
    ///
    /// - Parameters:
    ///   - erasureRoot: The erasure root
    ///   - shardIndex: The shard index to fetch
    ///   - segmentIndices: Segment indices to fetch
    ///   - assurerAddress: The assurer's network address
    /// - Returns: Tuple of (segment shards, justifications)
    /// - Throws: AvailabilityNetworkingError if request fails
    public func fetchSegmentShardsWithAvailabilityJustification(
        erasureRoot: Data32,
        shardIndex: UInt16,
        segmentIndices: [UInt16],
        from assurerAddress: NetAddr
    ) async throws -> ([Data], [AvailabilityJustification]) {
        // Delegate to CESegmentShardHandler
        guard let network else {
            logger.error("Network not set - call setNetwork() first")
            throw AvailabilityNetworkingError.peerManagerUnavailable
        }

        return try await CESegmentShardHandler.fetchSegmentShardsWithAvailabilityJustification(
            network: network,
            erasureRoot: erasureRoot,
            shardIndex: shardIndex,
            segmentIndices: segmentIndices,
            from: assurerAddress
        )
    }

    // MARK: - CE 148: Segment Request

    /// Fetch reconstructed segments from a guarantor
    ///
    /// Implements JAMNP-S CE 148: Segment request.
    /// Should fallback to CE 139/140 if this fails.
    ///
    /// Delegates to CE148Handler for the actual implementation.
    ///
    /// - Parameters:
    ///   - segmentsRoot: The segments root
    ///   - segmentIndices: Segment indices to fetch
    ///   - guarantorAddress: The guarantor's network address
    /// - Returns: Tuple of (segments, import proofs)
    /// - Throws: AvailabilityNetworkingError if request fails
    public func fetchSegments(
        segmentsRoot: Data32,
        segmentIndices: [UInt16],
        from guarantorAddress: NetAddr
    ) async throws -> ([Data4104], [[Data32]]) {
        // Delegate to CE148Handler
        guard let network else {
            logger.error("Network not set - call setNetwork() first")
            throw AvailabilityNetworkingError.peerManagerUnavailable
        }

        return try await CE148Handler.fetchSegments(
            network: network,
            segmentsRoot: segmentsRoot,
            segmentIndices: segmentIndices,
            from: guarantorAddress
        )
    }

    // MARK: - CE 147: Bundle Request

    /// Fetch a full work-package bundle from a guarantor
    ///
    /// Implements JAMNP-S CE 147: Bundle request.
    ///
    /// - Parameters:
    ///   - erasureRoot: The erasure root
    ///   - guarantorAddress: The guarantor's network address
    /// - Returns: The work-package bundle data
    /// - Throws: AvailabilityNetworkingError if request fails
    public func fetchBundle(
        erasureRoot: Data32,
        from guarantorAddress: NetAddr
    ) async throws -> Data {
        guard let network else {
            logger.error("Network not set - call setNetwork() first")
            throw AvailabilityNetworkingError.peerManagerUnavailable
        }

        return try await CE147Handler.fetchBundle(
            erasureRoot: erasureRoot,
            from: guarantorAddress,
            network: network
        )
    }

    // MARK: - Concurrent Fetching

    /// Fetch shards from multiple validators concurrently
    ///
    /// Collects responses until the required number of unique shards is obtained,
    /// then cancels remaining requests.
    ///
    /// - Parameters:
    ///   - erasureRoot: The erasure root
    ///   - shardIndices: Shard indices to fetch
    ///   - validators: Dictionary of validator index to network address
    ///   - coreIndex: The core index
    ///   - totalValidators: Total number of validators
    ///   - requiredShards: Minimum number of shards needed (default: 342)
    /// - Returns: Dictionary of shard index to shard data
    /// - Throws: AvailabilityNetworkingError if unable to collect enough shards
    public func fetchFromValidatorsConcurrently(
        erasureRoot: Data32,
        shardIndices: [UInt16],
        validators: [UInt16: NetAddr],
        coreIndex: UInt16,
        totalValidators: UInt16,
        requiredShards: Int = 342
    ) async throws -> [UInt16: Data] {
        guard let network else {
            logger.error("Network not set - call setNetwork() first")
            throw AvailabilityNetworkingError.peerManagerUnavailable
        }

        // Define the fetch operation to use CE 139
        let fetchOperation: @Sendable (_ erasureRoot: Data32, _ shardIndex: UInt16, _ address: NetAddr) async throws
            -> Data = { [network] erasureRoot, shardIndex, address in
                // Use CE 139 (fast mode) for individual shard fetching
                let requestData = try ShardRequest(
                    erasureRoot: erasureRoot,
                    shardIndex: shardIndex,
                    segmentIndices: []
                ).encode()

                let responseData = try await network.send(to: address, data: requestData)

                guard let response = responseData.first else {
                    throw AvailabilityNetworkingError.decodingFailed
                }

                return response
            }

        // Delegate to ConcurrentFetchHelpers
        return try await ConcurrentFetchHelpers.fetchFromValidatorsConcurrently(
            erasureRoot: erasureRoot,
            shardIndices: shardIndices,
            validators: validators,
            coreIndex: coreIndex,
            totalValidators: totalValidators,
            requiredShards: requiredShards,
            maxConcurrentRequests: maxConcurrentRequests,
            requestTimeout: requestTimeout,
            shardAssignment: shardAssignment,
            fetchOperation: fetchOperation
        )
    }
}

// Note: NetAddr is imported from Networking module
