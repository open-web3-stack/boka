import Foundation
import Utils

private let cEcOriginalCount = 342

/// Service for reconstructing data from erasure-coded shards
///
/// Handles checking reconstruction potential and performing data reconstruction
public actor ReconstructionService {
    private let dataStore: any DataStoreProtocol
    private let erasureCoding: ErasureCodingService

    public init(
        dataStore: any DataStoreProtocol,
        erasureCoding: ErasureCodingService
    ) {
        self.dataStore = dataStore
        self.erasureCoding = erasureCoding
    }

    /// Check if we can reconstruct data from local shards
    /// - Parameter erasureRoot: Erasure root identifying the data
    /// - Returns: True if at least 342 shards are available
    public func canReconstructLocally(erasureRoot: Data32) async throws -> Bool {
        let shardCount = try await dataStore.getShardCount(erasureRoot: erasureRoot)
        return shardCount >= cEcOriginalCount
    }

    /// Get reconstruction potential
    /// - Parameter erasureRoot: Erasure root identifying the data
    /// - Returns: Percentage of required shards available (capped at 100%)
    public func getReconstructionPotential(erasureRoot: Data32) async throws -> Double {
        let shardCount = try await dataStore.getShardCount(erasureRoot: erasureRoot)
        let percentage = Double(shardCount) / Double(cEcOriginalCount) * 100.0
        return min(percentage, 100.0)
    }

    /// Get missing shard indices
    /// - Parameter erasureRoot: Erasure root identifying the data
    /// - Returns: Array of missing shard indices
    public func getMissingShardIndices(erasureRoot: Data32) async throws -> [UInt16] {
        let availableIndices = try await dataStore.getAvailableShardIndices(erasureRoot: erasureRoot)
        let availableSet = Set(availableIndices)
        var missing: [UInt16] = []

        for i in 0 ..< 1023 where !availableSet.contains(UInt16(i)) {
            missing.append(UInt16(i))
        }

        return missing
    }

    /// Get reconstruction plan
    /// - Parameter erasureRoot: Erasure root identifying the data
    /// - Returns: Reconstruction plan with status and recommendations
    public func getReconstructionPlan(erasureRoot: Data32) async throws -> ReconstructionPlan {
        let localShards = try await dataStore.getShardCount(erasureRoot: erasureRoot)
        let missingShards = 1023 - localShards
        let canReconstruct = localShards >= cEcOriginalCount

        return ReconstructionPlan(
            erasureRoot: erasureRoot,
            localShards: localShards,
            missingShards: missingShards,
            canReconstructLocally: canReconstruct,
            reconstructionPercentage: Double(localShards) / Double(cEcOriginalCount) * 100.0
        )
    }

    /// Reconstruct data from local shards if possible
    /// - Parameters:
    ///   - erasureRoot: Erasure root identifying the data
    ///   - originalLength: Expected original data length
    /// - Returns: Reconstructed data
    public func reconstructFromLocalShards(erasureRoot: Data32, originalLength: Int) async throws -> Data {
        guard try await canReconstructLocally(erasureRoot: erasureRoot) else {
            let available = try await dataStore.getShardCount(erasureRoot: erasureRoot)
            throw ErasureCodingStoreError.insufficientShards(
                available: available,
                required: cEcOriginalCount
            )
        }

        let availableIndices = try await dataStore.getAvailableShardIndices(erasureRoot: erasureRoot)
        let shards = try await dataStore.getShards(
            erasureRoot: erasureRoot,
            shardIndices: Array(availableIndices.prefix(cEcOriginalCount))
        )

        return try await erasureCoding.reconstruct(shards: shards, originalLength: originalLength)
    }
}
