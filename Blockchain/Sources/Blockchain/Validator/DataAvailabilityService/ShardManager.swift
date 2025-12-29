import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "ShardManager")

/// Service for managing shard state and reconstruction planning
///
/// Provides methods to check shard availability, reconstruction capability,
/// and generate reconstruction plans by delegating to ErasureCodingDataStore
public actor ShardManager {
    private let erasureCodingDataStore: ErasureCodingDataStore?

    public init(erasureCodingDataStore: ErasureCodingDataStore?) {
        self.erasureCodingDataStore = erasureCodingDataStore
    }

    /// Get local shard availability for an erasure root
    /// - Parameter erasureRoot: The erasure root to check
    /// - Returns: Number of locally available shards
    public func getLocalShardCount(erasureRoot: Data32) async -> Int {
        guard let ecStore = erasureCodingDataStore else {
            logger.warning("ErasureCodingDataStore not available")
            return 0
        }

        do {
            return try await ecStore.getLocalShardCount(erasureRoot: erasureRoot)
        } catch {
            logger.error("Failed to get local shard count: \(error)")
            return 0
        }
    }

    /// Calculate reconstruction potential
    /// - Parameter erasureRoot: The erasure root to check
    /// - Returns: True if we have enough shards for reconstruction (>= 342)
    public func canReconstruct(erasureRoot: Data32) async -> Bool {
        guard let ecStore = erasureCodingDataStore else {
            return false
        }

        do {
            return try await ecStore.canReconstructLocally(erasureRoot: erasureRoot)
        } catch {
            logger.error("Failed to check reconstruction capability: \(error)")
            return false
        }
    }

    /// Get missing shard indices for an erasure root
    /// - Parameter erasureRoot: The erasure root to check
    /// - Returns: Array of missing shard indices
    public func getMissingShardIndices(erasureRoot: Data32) async -> [UInt16] {
        guard let ecStore = erasureCodingDataStore else {
            logger.warning("ErasureCodingDataStore not available")
            return []
        }

        do {
            return try await ecStore.getMissingShardIndices(erasureRoot: erasureRoot)
        } catch {
            logger.error("Failed to get missing shard indices: \(error)")
            return []
        }
    }

    /// Get reconstruction plan for an erasure root
    /// - Parameter erasureRoot: The erasure root to check
    /// - Returns: Reconstruction plan with detailed information
    public func getReconstructionPlan(erasureRoot: Data32) async -> ReconstructionPlan? {
        guard let ecStore = erasureCodingDataStore else {
            logger.warning("ErasureCodingDataStore not available")
            return nil
        }

        do {
            return try await ecStore.getReconstructionPlan(erasureRoot: erasureRoot)
        } catch {
            logger.error("Failed to get reconstruction plan: \(error)")
            return nil
        }
    }

    /// Fetch segments with automatic reconstruction if needed
    /// - Parameters:
    ///   - erasureRoot: The erasure root identifying the data
    ///   - indices: Segment indices to fetch
    /// - Returns: Array of segments
    public func fetchSegments(erasureRoot: Data32, indices: [Int]) async throws -> [Data4104] {
        guard let ecStore = erasureCodingDataStore else {
            throw DataAvailabilityError.segmentNotFound
        }

        // Try fetching with cache first
        return try await ecStore.getSegmentsWithCache(erasureRoot: erasureRoot, indices: indices)
    }

    /// Reconstruct data from local shards
    /// - Parameters:
    ///   - erasureRoot: The erasure root identifying the data
    ///   - originalLength: Original data length
    /// - Returns: Reconstructed data
    public func reconstructFromLocalShards(erasureRoot: Data32, originalLength: Int) async throws -> Data {
        guard let ecStore = erasureCodingDataStore else {
            throw DataAvailabilityError.segmentNotFound
        }

        return try await ecStore.reconstructFromLocalShards(
            erasureRoot: erasureRoot,
            originalLength: originalLength
        )
    }
}
