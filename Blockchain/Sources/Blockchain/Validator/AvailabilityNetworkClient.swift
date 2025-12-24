import Foundation
import Networking
import TracingUtils
import Utils

private let logger = Logger(label: "AvailabilityNetworkClient")

/// Network client for fetching availability shards via JAMNP-S protocols
///
/// Implements JAMNP-S CE 137/138/139/140/147/148 for shard distribution.
public actor AvailabilityNetworkClient {
    private let config: ProtocolConfigRef
    private let erasureCoding: ErasureCodingService
    private let shardAssignment: JAMNPSShardAssignment

    /// Peer manager for validator connections
    private var peerManager: PeerManager?

    /// Connection timeout in seconds
    private let connectionTimeout: TimeInterval = 5.0

    /// Request timeout in seconds
    private let requestTimeout: TimeInterval = 30.0

    /// Maximum concurrent requests
    private let maxConcurrentRequests: Int = 50

    /// Request deduplication cache
    private var pendingRequests: [String: Task<Data, Error>] = [:]

    public init(
        config: ProtocolConfigRef,
        erasureCoding: ErasureCodingService
    ) {
        self.config = config
        self.erasureCoding = erasureCoding
        shardAssignment = JAMNPSShardAssignment()
    }

    /// Set the peer manager for validator connections
    public func setPeerManager(_ peerManager: PeerManager) {
        self.peerManager = peerManager
    }

    // MARK: - CE 138: Audit Shard Request

    /// Fetch a single audit shard from an assurer
    ///
    /// Implements JAMNP-S CE 138: Audit shard request.
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
    ) async throws -> (Data, Justification) {
        let request = ShardRequest(erasureRoot: erasureRoot, shardIndex: shardIndex)
        let requestData = try request.encode()

        logger.debug(
            """
            Fetching audit shard \(shardIndex) from \(assurerAddress)
            """
        )

        let responseData = try await sendRequest(
            to: assurerAddress,
            requestType: .auditShard,
            data: requestData
        )

        let response = try ShardResponse.decode(responseData)

        // Verify we got a bundle shard
        guard !response.bundleShard.isEmpty else {
            throw AvailabilityNetworkingError.decodingFailed
        }

        // Justification should be the co-path from erasure-root to the shard
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
        let request = ShardRequest(
            erasureRoot: erasureRoot,
            shardIndex: shardIndex,
            segmentIndices: segmentIndices
        )
        let requestData = try request.encode()

        logger.debug(
            """
            Fetching \(segmentIndices.count) segment shards (shard \(shardIndex)) \
            from \(assurerAddress) using CE 139 (fast mode)
            """
        )

        let responseData = try await sendRequest(
            to: assurerAddress,
            requestType: .segmentShardsFast,
            data: requestData
        )

        let response = try ShardResponse.decode(responseData)

        logger.info(
            """
            Successfully fetched \(response.segmentShards.count) segment shards from \(assurerAddress)
            """
        )

        return response.segmentShards
    }

    /// Fetch segment shards with justification (CE 140)
    ///
    /// Use this when verification is needed (e.g., after detecting inconsistency).
    ///
    /// - Parameters:
    ///   - erasureRoot: The erasure root
    ///   - shardIndex: The shard index to fetch
    ///   - segmentIndices: Segment indices to fetch
    ///   - assurerAddress: The assurer's network address
    /// - Returns: Tuple of (segment shards, justifications)
    /// - Throws: AvailabilityNetworkingError if request fails
    public func fetchSegmentShardsWithJustification(
        erasureRoot: Data32,
        shardIndex: UInt16,
        segmentIndices: [UInt16],
        from assurerAddress: NetAddr
    ) async throws -> ([Data], [Justification]) {
        let request = ShardRequest(
            erasureRoot: erasureRoot,
            shardIndex: shardIndex,
            segmentIndices: segmentIndices
        )
        let requestData = try request.encode()

        logger.debug(
            """
            Fetching \(segmentIndices.count) segment shards (shard \(shardIndex)) \
            from \(assurerAddress) using CE 140 (verified mode)
            """
        )

        let responseData = try await sendRequest(
            to: assurerAddress,
            requestType: .segmentShardsVerified,
            data: requestData
        )

        let response = try ShardResponse.decode(responseData)

        // Extract justifications from the response
        // In CE 140, each segment shard should have a justification
        var justifications: [Justification] = []

        if case let .copath(steps) = response.justification {
            justifications = Array(repeating: .copath(steps), count: response.segmentShards.count)
        } else {
            justifications = Array(repeating: response.justification, count: response.segmentShards.count)
        }

        logger.info(
            """
            Successfully fetched \(response.segmentShards.count) verified segment shards from \(assurerAddress)
            """
        )

        return (response.segmentShards, justifications)
    }

    // MARK: - CE 147: Bundle Request

    /// Fetch a full work-package bundle from a guarantor
    ///
    /// Implements JAMNP-S CE 147: Bundle request.
    /// Should fallback to CE 138 if this fails.
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
        let request = BundleRequest(erasureRoot: erasureRoot)
        let requestData = request.encode()

        logger.debug(
            """
            Fetching bundle \(erasureRoot.hex) from \(guarantorAddress) using CE 147
            """
        )

        do {
            let responseData = try await sendRequest(
                to: guarantorAddress,
                requestType: .fullBundle,
                data: requestData
            )

            let response = try BundleResponse.decode(responseData)

            logger.info(
                """
                Successfully fetched bundle (\(response.bundle.count) bytes) from \(guarantorAddress)
                """
            )

            return response.bundle
        } catch {
            logger.warning(
                """
                Failed to fetch bundle via CE 147, would need to fallback to CE 138: \(error)
                """
            )
            throw error
        }
    }

    // MARK: - CE 148: Segment Request

    /// Fetch reconstructed segments from a guarantor
    ///
    /// Implements JAMNP-S CE 148: Segment request.
    /// Should fallback to CE 139/140 if this fails.
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
        let request = SegmentRequest(segmentsRoot: segmentsRoot, segmentIndices: segmentIndices)
        let requestData = try request.encode()

        logger.debug(
            """
            Fetching \(segmentIndices.count) segments from \(guarantorAddress) using CE 148
            """
        )

        do {
            let responseData = try await sendRequest(
                to: guarantorAddress,
                requestType: .reconstructedSegments,
                data: requestData
            )

            let response = try SegmentResponse.decode(responseData)

            logger.info(
                """
                Successfully fetched \(response.segments.count) segments from \(guarantorAddress)
                """
            )

            return (response.segments, response.importProofs)
        } catch {
            logger.warning(
                """
                Failed to fetch segments via CE 148, would need to fallback to CE 139/140: \(error)
                """
            )
            throw error
        }
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
        var collectedShards: [UInt16: Data] = [:]
        let requiredCount = requiredShards

        logger.info(
            """
            Starting concurrent fetch: need \(requiredCount) shards from \(validators.count) validators
            """
        )

        // Map validators to their assigned shard indices
        let validatorToShards = shardAssignment.getValidatorsForMissingShards(
            missingShardIndices: shardIndices,
            coreIndex: coreIndex,
            totalValidators: totalValidators
        )

        // Create fetch tasks for each validator
        var fetchTasks: [(validatorIndex: UInt16, task: Task<(UInt16, Data), Error>)] = []

        for (validatorIndex, address) in validators {
            guard let assignedShards = validatorToShards[validatorIndex] else {
                continue
            }

            // Fetch the first assigned shard from this validator
            let shardIndex = assignedShards[0]

            let task = Task<Data, Error> {
                try await fetchAuditShard(
                    erasureRoot: erasureRoot,
                    shardIndex: shardIndex,
                    from: address
                ).0
            }

            fetchTasks.append((validatorIndex, Task {
                try await (shardIndex, task.value)
            }))
        }

        // Collect results with timeout
        let startTime = Date()
        var completedTasks = 0

        for (validatorIndex, task) in fetchTasks {
            // Check if we have enough shards
            if collectedShards.count >= requiredCount {
                logger.info(
                    """
                    Collected sufficient shards (\(collectedShards.count)/\(requiredCount)), \
                    cancelling remaining requests
                    """
                )
                break
            }

            // Check timeout
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed > requestTimeout {
                logger.warning(
                    """
                    Request timeout after \(elapsed)s, collected \(collectedShards.count)/\(requiredCount) shards
                    """
                )
                break
            }

            do {
                // Use adaptive timeout based on response rate
                let adaptiveTimeout = max(1.0, requestTimeout - elapsed)
                let result = try await withThrowingTaskGroup(of: (UInt16, Data).self) { group in
                    group.addTask {
                        try await task.value
                    }

                    return try await group.next(timeout: adaptiveTimeout) ?? {
                        throw AvailabilityNetworkingError.decodingFailed
                    }()
                }

                collectedShards[result.0] = result.1
                completedTasks += 1

                logger.trace(
                    """
                    Collected shard \(result.0) from validator \(validatorIndex), \
                    total: \(collectedShards.count)/\(requiredCount)
                    """
                )
            } catch {
                logger.warning(
                    """
                    Failed to fetch shard from validator \(validatorIndex): \(error)
                    """
                )
            }
        }

        // Verify we collected enough shards
        guard collectedShards.count >= requiredCount else {
            logger.error(
                """
                Insufficient shards collected: \(collectedShards.count)/\(requiredCount)
                """
            )
            throw AvailabilityNetworkingError.decodingFailed
        }

        logger.info(
            """
            Successfully collected \(collectedShards.count) shards from \(completedTasks) validators
            """
        )

        return collectedShards
    }

    // MARK: - Helper Methods

    /// Send a request to a validator
    private func sendRequest(
        to address: NetAddr,
        requestType: ShardRequestType,
        data: Data
    ) async throws -> Data {
        // Check for duplicate requests
        let cacheKey = "\(address):\(requestType.rawValue):\(data.blake2b256hash().hex)"

        if let existingTask = pendingRequests[cacheKey] {
            logger.trace("Deduplicating request: \(cacheKey)")
            return try await existingTask.value
        }

        // Create new request task
        let task = Task<Data, Error> {
            // This integrates with the PeerManager and Connection infrastructure
            // TODO: Implement actual network request handling:
            // 1. Get or create a connection to the validator
            // 2. Send the request via the appropriate CE protocol (137-140, 147-148)
            // 3. Await and decode the response
            // 4. Handle errors and retries with exponential backoff

            throw AvailabilityNetworkingError.decodingFailed
        }

        pendingRequests[cacheKey] = task

        do {
            let result = try await task.value
            pendingRequests.removeValue(forKey: cacheKey)
            return result
        } catch {
            pendingRequests.removeValue(forKey: cacheKey)
            throw error
        }
    }
}

// MARK: - Timeout Extension

extension TaskGroup where Failure == Error {
    func next(timeout: TimeInterval) async throws -> T? {
        try await withThrowingTaskGroup(of: T?.self) { group in
            group.addTask {
                try await self.next()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }

            guard let result = try await group.next() else {
                return nil
            }

            group.cancelAll()

            return result
        }
    }
}

// MARK: - Fetch Strategy

/// Strategy for fetching shards
public enum FetchStrategy: Sendable {
    /// Fast mode: Use CE 139 (no justification)
    case fast

    /// Verified mode: Use CE 140 (with justification)
    case verified

    /// Adaptive: Start with CE 139, fallback to CE 140 on inconsistency
    case adaptive

    /// Local-only: Don't use network, only local shards
    case localOnly
}

// MARK: - Placeholder PeerManager

/// Placeholder for PeerManager integration
///
/// In production, this would be the actual PeerManager from the Node module.
public struct PeerManager {
    // Placeholder - would contain connection management logic
}

/// Validator network address
public struct NetAddr: Sendable, Hashable {
    public let ip: String
    public let port: UInt16

    public init(ip: String, port: UInt16) {
        self.ip = ip
        self.port = port
    }
}
