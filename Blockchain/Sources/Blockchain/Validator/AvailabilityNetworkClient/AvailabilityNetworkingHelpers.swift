import Foundation
import Networking
import TracingUtils
import Utils

private let logger = Logger(label: "AvailabilityNetworkingHelpers")

// MARK: - Concurrent Fetching Helpers

/// Helper methods for concurrent shard fetching operations
public enum ConcurrentFetchHelpers {
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
    ///   - maxConcurrentRequests: Maximum concurrent requests (default: 50)
    ///   - requestTimeout: Request timeout in seconds (default: 30.0)
    ///   - fetchOperation: Async operation to fetch a single shard
    /// - Returns: Dictionary of shard index to shard data
    /// - Throws: AvailabilityNetworkingError if unable to collect enough shards
    public static func fetchFromValidatorsConcurrently(
        erasureRoot: Data32,
        shardIndices: [UInt16],
        validators: [UInt16: NetAddr],
        coreIndex: UInt16,
        totalValidators: UInt16,
        requiredShards: Int = 342,
        maxConcurrentRequests: Int = 50,
        requestTimeout: TimeInterval = 30.0,
        shardAssignment: JAMNPSShardAssignment,
        fetchOperation: @Sendable @escaping (_ erasureRoot: Data32, _ shardIndex: UInt16, _ address: NetAddr) async throws -> Data,
    ) async throws -> [UInt16: Data] {
        var collectedShards: [UInt16: Data] = [:]
        let requiredCount = requiredShards

        logger.info(
            """
            Starting concurrent fetch: need \(requiredCount) shards from \(validators.count) validators \
            (max concurrent: \(maxConcurrentRequests))
            """,
        )

        // Map validators to their assigned shard indices
        let validatorToShards = await shardAssignment.getValidatorsForMissingShards(
            missingShardIndices: shardIndices,
            coreIndex: coreIndex,
            totalValidators: totalValidators,
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

        try await withThrowingTaskGroup(of: (UInt16, UInt16, Data)?.self) { group in
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
                        do {
                            let shardData = try await fetchOperation(erasureRoot, pair.shardIndex, pair.address)
                            return (pair.validatorIndex, pair.shardIndex, shardData)
                        } catch {
                            logger.debug("Fetch failed from validator \(pair.validatorIndex): \(error)")
                            // Return nil to indicate failure without cancelling the entire group
                            return nil
                        }
                    }
                }
            }

            // Initial batch of tasks
            addTasksIfNeeded()

            // Process results as they complete
            while let result = try await group.next() {
                activeTasks -= 1
                completedTasks += 1

                // Check timeout
                let elapsed = Date().timeIntervalSince(startTime)
                if elapsed > requestTimeout {
                    logger.warning(
                        """
                        Request timeout after \(elapsed)s, collected \(collectedShards.count)/\(requiredCount) shards
                        """,
                    )
                    group.cancelAll()
                    break
                }

                // Collect the result (skip nil results from failed fetches)
                guard let (validatorIndex, shardIndex, shardData) = result else {
                    continue
                }

                collectedShards[shardIndex] = shardData

                logger.trace(
                    """
                    Collected shard \(shardIndex) from validator \(validatorIndex), \
                    total: \(collectedShards.count)/\(requiredCount)
                    """,
                )

                // Check if we have enough shards
                if collectedShards.count >= requiredCount {
                    logger.info(
                        """
                        Collected sufficient shards (\(collectedShards.count)/\(requiredCount)), \
                        cancelling remaining requests
                        """,
                    )
                    group.cancelAll()
                    break
                }

                // Add more tasks if available
                addTasksIfNeeded()
            }
        }

        // Verify we collected enough shards
        guard collectedShards.count >= requiredCount else {
            logger.error(
                """
                Insufficient shards collected: \(collectedShards.count)/\(requiredCount)
                """,
            )
            throw AvailabilityNetworkingError.decodingFailed
        }

        logger.info(
            """
            Successfully collected \(collectedShards.count) shards from \(completedTasks) validators
            """,
        )

        return collectedShards
    }
}

// MARK: - Request Sending Helpers

/// Helper methods for sending requests with deduplication and timeout
public actor RequestSendingHelpers {
    /// Request deduplication cache
    private var pendingRequests: [String: Task<Data, Error>] = [:]

    /// Network metrics tracking
    private var metrics = NetworkMetrics()

    /// Request timeout in seconds
    private let requestTimeout: TimeInterval = 30.0

    /// Send a request to a validator with deduplication and timeout
    ///
    /// - Parameters:
    ///   - address: The validator's network address
    ///   - requestType: The type of shard request
    ///   - data: The request data
    ///   - network: The network protocol to use
    /// - Returns: The response data
    /// - Throws: AvailabilityNetworkingError if request fails
    public func sendRequest(
        to address: NetAddr,
        requestType: ShardRequestType,
        data: Data,
        network: any AvailabilityNetworkProtocol,
    ) async throws -> Data {
        // Use the request type and entire data for cache key to avoid collisions
        // Hash the entire data since prefix(64) could collide for segment requests
        let dataHash = data.blake2b256hash().toHexString()
        let cacheKey = "\(address):\(requestType.rawValue):\(dataHash)"

        // Check for duplicate requests
        if let existingTask = pendingRequests[cacheKey] {
            logger.trace("Deduplicating request: \(cacheKey)")
            return try await existingTask.value
        }

        // Create new request task
        let startTime = Date()
        let task = Task<Data, Error> {
            // Send the request via Network
            logger.debug("Sending \(requestType) request to \(address)")

            // Send request and get response
            let responseData = try await network.send(to: address, data: data)

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

    /// Get current network metrics
    /// - Returns: Network performance metrics
    public func getNetworkMetrics() -> NetworkMetrics {
        metrics
    }

    /// Reset network metrics
    public func resetNetworkMetrics() {
        metrics = NetworkMetrics()
    }

    // MARK: - Private Metrics Methods

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
}
