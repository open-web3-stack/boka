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

    /// Network protocol for sending requests
    private var network: (any NetworkProtocol)?

    /// Connection timeout in seconds
    private let connectionTimeout: TimeInterval = 5.0

    /// Request timeout in seconds
    private let requestTimeout: TimeInterval = 30.0

    /// Maximum concurrent requests
    private let maxConcurrentRequests: Int = 50

    /// Request deduplication cache
    private var pendingRequests: [String: Task<Data, Error>] = [:]

    /// Network metrics tracking
    private var metrics = NetworkMetrics()

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
    public func setNetwork(_ network: any NetworkProtocol) {
        self.network = network
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

        // Record CE 138 fallback usage
        await recordCE138Request()

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

        // Record CE 139 fallback usage
        await recordCE139Request()

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

        // Record CE 140 fallback usage
        await recordCE140Request()

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

        // Record CE 147 fallback usage
        await recordCE147Request()

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

        // Record CE 148 fallback usage
        await recordCE148Request()

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
            Starting concurrent fetch: need \(requiredCount) shards from \(validators.count) validators \
            (max concurrent: \(maxConcurrentRequests))
            """
        )

        // Map validators to their assigned shard indices
        let validatorToShards = shardAssignment.getValidatorsForMissingShards(
            missingShardIndices: shardIndices,
            coreIndex: coreIndex,
            totalValidators: totalValidators
        )

        // Prepare validator/shard pairs to fetch
        var fetchPairs: [(validatorIndex: UInt16, shardIndex: UInt16, address: NetAddr)] = []
        for (validatorIndex, address) in validators {
            guard let assignedShards = validatorToShards[validatorIndex] else {
                continue
            }
            // Fetch the first assigned shard from this validator
            fetchPairs.append((validatorIndex, assignedShards[0], address))
        }

        // Use TaskGroup with controlled concurrency via a semaphore
        let startTime = Date()
        var completedTasks = 0

        try await withThrowingTaskGroup(of: (UInt16, UInt16, Data).self) { group in
            // Semaphore to limit concurrent tasks
            var activeTasks = 0
            var currentIndex = 0

            // Helper to add tasks up to the concurrency limit
            func addTasksIfNeeded() {
                while activeTasks < maxConcurrentRequests, currentIndex < fetchPairs.count {
                    let pair = fetchPairs[currentIndex]
                    currentIndex += 1
                    activeTasks += 1

                    group.addTask {
                        let shardData = try await self.fetchAuditShard(
                            erasureRoot: erasureRoot,
                            shardIndex: pair.shardIndex,
                            from: pair.address
                        ).0
                        return (pair.validatorIndex, pair.shardIndex, shardData)
                    }
                }
            }

            // Initial batch of tasks
            addTasksIfNeeded()

            // Process results as they complete
            while await group.next() != nil {
                activeTasks -= 1
                completedTasks += 1

                // Check timeout
                let elapsed = Date().timeIntervalSince(startTime)
                if elapsed > requestTimeout {
                    logger.warning(
                        """
                        Request timeout after \(elapsed)s, collected \(collectedShards.count)/\(requiredCount) shards
                        """
                    )
                    group.cancelAll()
                    break
                }

                // Collect the result
                if let result = try await group.next() {
                    collectedShards[result.1] = result.2

                    logger.trace(
                        """
                        Collected shard \(result.1) from validator \(result.0), \
                        total: \(collectedShards.count)/\(requiredCount)
                        """
                    )

                    // Check if we have enough shards
                    if collectedShards.count >= requiredCount {
                        logger.info(
                            """
                            Collected sufficient shards (\(collectedShards.count)/\(requiredCount)), \
                            cancelling remaining requests
                            """
                        )
                        group.cancelAll()
                        break
                    }

                    // Add more tasks if available
                    addTasksIfNeeded()
                }
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
        let startTime = Date()
        let task = Task<Data, Error> {
            // Use Network to send the actual network request
            guard let network else {
                logger.error("Network not set - call setNetwork() first")
                throw AvailabilityNetworkingError.peerManagerUnavailable
            }

            // Determine the CERequest type based on requestType
            let ceRequest: CERequest
            switch requestType {
            case .shardDistribution:
                // Decode ShardDistribution from data
                let decoder = JamDecoder(data: data, config: config)
                let erasureRoot = try decoder.decode(Data32.self)
                let shardIndex = try decoder.decode(UInt16.self)
                ceRequest = .shardDistribution(ShardDistributionMessage(
                    erasureRoot: erasureRoot,
                    shardIndex: shardIndex
                ))

            case .auditShard:
                // Decode AuditShardRequest from data
                let decoder = JamDecoder(data: data, config: config)
                let erasureRoot = try decoder.decode(Data32.self)
                let shardIndex = try decoder.decode(UInt16.self)
                ceRequest = .auditShardRequest(AuditShardRequestMessage(
                    erasureRoot: erasureRoot,
                    shardIndex: shardIndex
                ))

            case .segmentShardFast, .segmentShardVerified:
                // Decode SegmentShardRequest from data
                let decoder = JamDecoder(data: data, config: config)
                let erasureRoot = try decoder.decode(Data32.self)
                let shardIndex = try decoder.decode(UInt16.self)
                let segmentCount = try decoder.decode(UInt32.self)
                var segmentIndices: [UInt16] = []
                for _ in 0 ..< segmentCount {
                    try segmentIndices.append(decoder.decode(UInt16.self))
                }

                let message = SegmentShardRequestMessage(
                    erasureRoot: erasureRoot,
                    shardIndex: shardIndex,
                    segmentIndices: segmentIndices
                )

                // Use fast or verified variant
                if requestType == .segmentShardFast {
                    ceRequest = .segmentShardRequest1(message)
                } else {
                    ceRequest = .segmentShardRequest2(message)
                }

            case .bundle:
                // Decode bundle request from data
                let decoder = JamDecoder(data: data, config: config)
                let erasureRoot = try decoder.decode(Data32.self)
                ceRequest = .blockRequest(BlockRequest(
                    hash: erasureRoot,
                    direction: .descendingInclusive,
                    maxBlocks: 1
                ))

            case .segment:
                // Decode segment request from data
                let decoder = JamDecoder(data: data, config: config)
                let segmentsRoot = try decoder.decode(Data32.self)
                let segmentCount = try decoder.decode(UInt32.self)
                var segmentIndices: [UInt16] = []
                for _ in 0 ..< segmentCount {
                    try segmentIndices.append(decoder.decode(UInt16.self))
                }
                // Note: CE 148 not fully implemented yet
                throw AvailabilityNetworkingError.unsupportedProtocol
            }

            // Send the request via Network
            logger.debug("Sending \(requestType) request to \(address)")

            // Send request and get response
            let responseData = try await network.send(to: address, message: ceRequest)

            // Response should be a single Data blob
            guard let response = responseData.first else {
                logger.error("Empty response from \(address)")
                throw AvailabilityNetworkingError.decodingFailed
            }

            logger.debug("Received response: \(response.count) bytes")
            return response
        }

        pendingRequests[cacheKey] = task

        do {
            let result = try await task.value
            let latency = Date().timeIntervalSince(startTime)

            // Record success metrics
            recordSuccess(latency: latency)

            pendingRequests.removeValue(forKey: cacheKey)
            return result
        } catch {
            let latency = Date().timeIntervalSince(startTime)

            // Record failure metrics (considered a retry if timeout occurred)
            let wasRetry = latency >= requestTimeout
            recordFailure(wasRetry: wasRetry)

            pendingRequests.removeValue(forKey: cacheKey)
            throw error
        }
    }

    // MARK: - Metrics

    /// Get current network metrics
    /// - Returns: Network performance metrics
    public func getNetworkMetrics() -> NetworkMetrics {
        metrics
    }

    /// Reset network metrics
    public func resetNetworkMetrics() {
        metrics = NetworkMetrics()
    }

    /// Record a successful request
    private func recordSuccess(latency: TimeInterval) {
        metrics.totalRequests += 1
        metrics.successfulRequests += 1
        metrics.totalLatency += latency

        // Update min/max latency
        if latency < metrics.minLatency {
            metrics.minLatency = latency
        }
        if latency > metrics.maxLatency {
            metrics.maxLatency = latency
        }

        // Track recent latencies (last 100)
        metrics.recentLatencies.append(latency)
        if metrics.recentLatencies.count > 100 {
            metrics.recentLatencies.removeFirst()
        }
    }

    /// Record a failed request
    private func recordFailure(wasRetry: Bool) {
        metrics.totalRequests += 1
        metrics.failedRequests += 1

        if wasRetry {
            metrics.totalRetries += 1
        }
    }

    // MARK: - Fallback Metrics Recording

    /// Record when data is found locally (no network request needed)
    private func recordLocalHit() {
        metrics.localHits += 1
    }

    /// Record a CE 138 request (Audit Shard Request)
    private func recordCE138Request() {
        metrics.ce138Requests += 1
        metrics.fallbackCount += 1
    }

    /// Record a CE 139 request (Segment Shard Request - fast)
    private func recordCE139Request() {
        metrics.ce139Requests += 1
        metrics.fallbackCount += 1
    }

    /// Record a CE 140 request (Segment Shard Request - verified)
    private func recordCE140Request() {
        metrics.ce140Requests += 1
        metrics.fallbackCount += 1
    }

    /// Record a CE 147 request (Bundle Request)
    private func recordCE147Request() {
        metrics.ce147Requests += 1
        metrics.fallbackCount += 1
    }

    /// Record a CE 148 request (Segment Request)
    private func recordCE148Request() {
        metrics.ce148Requests += 1
        metrics.fallbackCount += 1
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

    /// Adaptive: Start with CE 139, fallback to CE 140
    case adaptive

    /// Local-only: Don't use network, only local shards
    case localOnly
}

// MARK: - Network Metrics

/// Network operation metrics
public struct NetworkMetrics: Sendable {
    /// Total number of requests made
    public var totalRequests: Int = 0

    /// Number of successful requests
    public var successfulRequests: Int = 0

    /// Number of failed requests
    public var failedRequests: Int = 0

    /// Total number of retries
    public var totalRetries: Int = 0

    /// Total latency across all requests (seconds)
    public var totalLatency: TimeInterval = 0

    /// Minimum request latency (seconds)
    public var minLatency: TimeInterval = .infinity

    /// Maximum request latency (seconds)
    public var maxLatency: TimeInterval = 0

    /// Recent request latencies (last 100)
    public var recentLatencies: [TimeInterval] = []

    // MARK: - Fallback Usage Tracking

    /// Number of requests served from local storage
    public var localHits: Int = 0

    /// Number of CE 138 requests (Audit Shard Request)
    public var ce138Requests: Int = 0

    /// Number of CE 139 requests (Segment Shard Request - fast)
    public var ce139Requests: Int = 0

    /// Number of CE 140 requests (Segment Shard Request - verified)
    public var ce140Requests: Int = 0

    /// Number of CE 147 requests (Bundle Request)
    public var ce147Requests: Int = 0

    /// Number of CE 148 requests (Segment Request)
    public var ce148Requests: Int = 0

    /// Number of fallback operations (local → network)
    public var fallbackCount: Int = 0

    /// Average request latency
    public var averageLatency: TimeInterval {
        guard successfulRequests > 0 else { return 0 }
        return totalLatency / Double(successfulRequests)
    }

    /// Request success rate (0.0 to 1.0)
    public var successRate: Double {
        guard totalRequests > 0 else { return 1.0 }
        return Double(successfulRequests) / Double(totalRequests)
    }

    /// Median latency from recent samples
    public var medianLatency: TimeInterval {
        guard !recentLatencies.isEmpty else { return 0 }
        let sorted = recentLatencies.sorted()
        let count = sorted.count
        if count % 2 == 0 {
            return (sorted[count / 2 - 1] + sorted[count / 2]) / 2
        } else {
            return sorted[count / 2]
        }
    }

    /// P95 latency from recent samples
    public var p95Latency: TimeInterval {
        guard !recentLatencies.isEmpty else { return 0 }
        let sorted = recentLatencies.sorted()
        let index = Int(Double(sorted.count) * 0.95)
        return sorted[min(index, sorted.count - 1)]
    }

    /// P99 latency from recent samples
    public var p99Latency: TimeInterval {
        guard !recentLatencies.isEmpty else { return 0 }
        let sorted = recentLatencies.sorted()
        let index = Int(Double(sorted.count) * 0.99)
        return sorted[min(index, sorted.count - 1)]
    }

    public init() {}

    // MARK: - Fallback Tracking Methods

    /// Record when data is found locally (no network request)
    public mutating func recordLocalHit() {
        localHits += 1
    }

    /// Record a CE 138 request (Audit Shard Request)
    public mutating func recordCE138Request() {
        ce138Requests += 1
        fallbackCount += 1
    }

    /// Record a CE 139 request (Segment Shard Request - fast)
    public mutating func recordCE139Request() {
        ce139Requests += 1
        fallbackCount += 1
    }

    /// Record a CE 140 request (Segment Shard Request - verified)
    public mutating func recordCE140Request() {
        ce140Requests += 1
        fallbackCount += 1
    }

    /// Record a CE 147 request (Bundle Request)
    public mutating func recordCE147Request() {
        ce147Requests += 1
        fallbackCount += 1
    }

    /// Record a CE 148 request (Segment Request)
    public mutating func recordCE148Request() {
        ce148Requests += 1
        fallbackCount += 1
    }
}

// MARK: - Fallback Timeout Configuration

/// Timeout configuration for each stage of the fallback chain
public struct FallbackTimeoutConfig: Sendable {
    /// Timeout for local operations (default: 0.1s)
    public var localTimeout: TimeInterval

    /// Timeout for CE 147 (Bundle Request from guarantors) (default: 5s)
    public var ce147Timeout: TimeInterval

    /// Timeout for CE 138 (Audit Shard Request) (default: 5s)
    public var ce138Timeout: TimeInterval

    /// Timeout for CE 139 (Segment Shard Request - fast) (default: 3s)
    public var ce139Timeout: TimeInterval

    /// Timeout for CE 140 (Segment Shard Request - verified) (default: 10s)
    public var ce140Timeout: TimeInterval

    /// Timeout for CE 148 (Segment Request from guarantors) (default: 5s)
    public var ce148Timeout: TimeInterval

    public init(
        localTimeout: TimeInterval = 0.1,
        ce147Timeout: TimeInterval = 5.0,
        ce138Timeout: TimeInterval = 5.0,
        ce139Timeout: TimeInterval = 3.0,
        ce140Timeout: TimeInterval = 10.0,
        ce148Timeout: TimeInterval = 5.0
    ) {
        self.localTimeout = localTimeout
        self.ce147Timeout = ce147Timeout
        self.ce138Timeout = ce138Timeout
        self.ce139Timeout = ce139Timeout
        self.ce140Timeout = ce140Timeout
        self.ce148Timeout = ce148Timeout
    }
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
