import Foundation
import Networking
import TracingUtils
import Utils

private let logger = Logger(label: "BatchOperations")
private let cEcOriginalCount = 342

/// Service for batch operations on segments and reconstruction
public actor BatchOperations {
    private let dataStore: any DataStoreProtocol
    private let d3lStore: D3LSegmentStore
    private let shardRetrieval: ShardRetrieval
    private let reconstructionService: ReconstructionService

    public init(
        dataStore: any DataStoreProtocol,
        d3lStore: D3LSegmentStore,
        shardRetrieval: ShardRetrieval,
        reconstructionService: ReconstructionService,
    ) {
        self.dataStore = dataStore
        self.d3lStore = d3lStore
        self.shardRetrieval = shardRetrieval
        self.reconstructionService = reconstructionService
    }

    /// Batch get segments for multiple erasure roots
    /// - Parameter requests: Array of segment requests
    /// - Returns: Dictionary mapping erasure root to segments
    public func batchGetSegments(requests: [BatchSegmentRequest]) async throws -> [Data32: [Data4104]] {
        var results: [Data32: [Data4104]] = [:]

        for request in requests {
            do {
                let segments = try await d3lStore.getSegments(
                    erasureRoot: request.erasureRoot,
                    indices: request.indices,
                )
                results[request.erasureRoot] = segments
            } catch {
                logger.warning("Failed to retrieve segments for erasureRoot=\(request.erasureRoot.toHexString()): \(error)")
            }
        }

        return results
    }

    /// Batch reconstruction for multiple erasure roots with network fallback
    /// - Parameters:
    ///   - erasureRoots: Erasure roots to reconstruct
    ///   - originalLengths: Mapping of erasure root to original length
    ///   - validators: Optional validator addresses for network fallback
    ///   - coreIndex: Core index for shard assignment (default: 0)
    ///   - totalValidators: Total number of validators (default: 1023)
    /// - Returns: Dictionary mapping erasure root to reconstructed data
    public func batchReconstruct(
        erasureRoots: [Data32],
        originalLengths: [Data32: Int],
        networkClient: AvailabilityNetworkClient?,
        fetchStrategy: FetchStrategy,
        validators: [UInt16: NetAddr]? = nil,
        coreIndex: UInt16 = 0,
        totalValidators: UInt16 = 1023,
    ) async throws -> [Data32: Data] {
        // Capture state for TaskGroup closures
        let dataStore = dataStore
        let networkClient = networkClient
        let fetchStrategy = fetchStrategy

        // Limit concurrency
        let maxConcurrentTasks = 10

        // Parallelize reconstruction across erasure roots
        return try await withThrowingTaskGroup(of: (Data32, Data).self) { group in
            var results: [Data32: Data] = [:]
            var activeTasks = 0
            var iterator = erasureRoots.makeIterator()

            // Helper to add next task
            func addNextTask() {
                guard let erasureRoot = iterator.next() else { return }

                activeTasks += 1
                group.addTask {
                    // Check local availability first
                    let canReconstructLocally = try await self.reconstructionService.canReconstructLocally(erasureRoot: erasureRoot)

                    if canReconstructLocally {
                        // Try local reconstruction first
                        do {
                            let data = try await self.reconstructionService.reconstructFromLocalShards(
                                erasureRoot: erasureRoot,
                                originalLength: originalLengths[erasureRoot] ?? 0,
                            )
                            return (erasureRoot, data)
                        } catch {
                            logger.warning("Local reconstruction failed for erasureRoot=\(erasureRoot.toHexString()): \(error)")
                        }
                    }

                    // Try network fallback if enabled and validators available
                    if fetchStrategy != .localOnly,
                       let client = networkClient,
                       let validatorAddrs = validators,
                       !validatorAddrs.isEmpty
                    {
                        do {
                            logger.info("Attempting network fallback for erasureRoot=\(erasureRoot.toHexString())")

                            let missingShards = try await self.reconstructionService.getMissingShardIndices(erasureRoot: erasureRoot)

                            // Fetch missing shards from network
                            let fetchedShards = try await client.fetchFromValidatorsConcurrently(
                                erasureRoot: erasureRoot,
                                shardIndices: missingShards,
                                validators: validatorAddrs,
                                coreIndex: coreIndex,
                                totalValidators: totalValidators,
                                requiredShards: max(
                                    0,
                                    cEcOriginalCount - (self.shardRetrieval.getLocalShardCount(erasureRoot: erasureRoot)),
                                ),
                            )

                            // Store fetched shards locally
                            // NOTE: Currently storing to dataStore (RocksDB) for simplicity
                            // TODO: For D³L segments (which this is), should ideally use filesystemStore
                            // for consistency with storeExportedSegments. However:
                            // 1. D3LSegmentStore.storeSegments() expects all 1023 shards together
                            // 2. Individual shard storage to filesystemStore bypasses erasure coding metadata
                            // 3. Proper fix requires either:
                            //    - Adding batch store method to D3LSegmentStore
                            //    - Or implementing D³L shard lifecycle management
                            // See GP spec sections 10.3-10.4 for D³L retention requirements
                            for (shardIndex, shardData) in fetchedShards {
                                try await dataStore.storeShard(
                                    shardData: shardData,
                                    erasureRoot: erasureRoot,
                                    shardIndex: shardIndex,
                                )
                            }

                            // Now reconstruct with combined local + fetched shards
                            let data = try await self.reconstructionService.reconstructFromLocalShards(
                                erasureRoot: erasureRoot,
                                originalLength: originalLengths[erasureRoot] ?? 0,
                            )

                            logger.info("Successfully reconstructed erasureRoot=\(erasureRoot.toHexString()) with network fallback")
                            return (erasureRoot, data)
                        } catch {
                            logger.error("Network fallback failed for erasureRoot=\(erasureRoot.toHexString()): \(error)")
                            throw error
                        }
                    } else {
                        // No network fallback available, throw error
                        let localShardCount = try await self.shardRetrieval.getLocalShardCount(erasureRoot: erasureRoot)
                        throw ErasureCodingStoreError.insufficientShards(available: localShardCount, required: cEcOriginalCount)
                    }
                }
            }

            // Start initial batch
            for _ in 0 ..< maxConcurrentTasks {
                addNextTask()
            }

            // Process results and schedule new tasks
            while activeTasks > 0 {
                if let (erasureRoot, data) = try await group.next() {
                    results[erasureRoot] = data
                    activeTasks -= 1
                    addNextTask()
                } else {
                    // Should not happen if activeTasks > 0, but break to avoid infinite loop
                    break
                }
            }

            return results
        }
    }

    /// Batch reconstruction from local shards only
    private func batchReconstructFromLocal(
        erasureRoots: [Data32],
        originalLengths: [Data32: Int],
    ) async throws -> [Data32: Data] {
        // Parallelize local reconstruction
        try await withThrowingTaskGroup(of: (Data32, Data?).self) { group in
            for erasureRoot in erasureRoots {
                group.addTask {
                    guard let originalLength = originalLengths[erasureRoot] else {
                        logger.warning("Missing original length for erasureRoot=\(erasureRoot.toHexString())")
                        return (erasureRoot, nil)
                    }

                    do {
                        let data = try await self.reconstructionService.reconstructFromLocalShards(
                            erasureRoot: erasureRoot,
                            originalLength: originalLength,
                        )
                        return (erasureRoot, data)
                    } catch {
                        logger.warning("Failed to reconstruct erasureRoot=\(erasureRoot.toHexString()): \(error)")
                        return (erasureRoot, nil)
                    }
                }
            }

            // Collect all results
            var results: [Data32: Data] = [:]
            for try await (erasureRoot, data) in group {
                if let data {
                    results[erasureRoot] = data
                }
            }
            return results
        }
    }
}
