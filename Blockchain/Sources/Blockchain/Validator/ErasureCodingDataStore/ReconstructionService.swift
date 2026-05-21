import Foundation
import Utils

private let cEcOriginalCount = 342

/// Service for reconstructing data from erasure-coded shards
///
/// Handles checking reconstruction potential and performing data reconstruction
public actor ReconstructionService {
    private let dataStore: any DataStoreProtocol
    private let filesystemStore: FilesystemDataStore
    private let erasureCoding: ErasureCodingService

    public init(
        dataStore: any DataStoreProtocol,
        filesystemStore: FilesystemDataStore,
        erasureCoding: ErasureCodingService,
    ) {
        self.dataStore = dataStore
        self.filesystemStore = filesystemStore
        self.erasureCoding = erasureCoding
    }

    /// Check if we can reconstruct data from local shards
    /// - Parameter erasureRoot: Erasure root identifying the data
    /// - Returns: True if at least 342 shards are available
    public func canReconstructLocally(erasureRoot: Data32) async throws -> Bool {
        let shardCount = try await getLocalShardCount(erasureRoot: erasureRoot)
        return shardCount >= cEcOriginalCount
    }

    /// Get reconstruction potential
    /// - Parameter erasureRoot: Erasure root identifying the data
    /// - Returns: Percentage of required shards available (capped at 100%)
    public func getReconstructionPotential(erasureRoot: Data32) async throws -> Double {
        let shardCount = try await getLocalShardCount(erasureRoot: erasureRoot)
        let percentage = Double(shardCount) / Double(cEcOriginalCount) * 100.0
        return min(percentage, 100.0)
    }

    /// Get missing shard indices
    /// - Parameter erasureRoot: Erasure root identifying the data
    /// - Returns: Array of missing shard indices
    public func getMissingShardIndices(erasureRoot: Data32) async throws -> [UInt16] {
        let availableIndices = try await getLocalShardIndices(erasureRoot: erasureRoot)
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
        let localShards = try await getLocalShardCount(erasureRoot: erasureRoot)
        let missingShards = 1023 - localShards
        let canReconstruct = localShards >= cEcOriginalCount

        return ReconstructionPlan(
            erasureRoot: erasureRoot,
            localShards: localShards,
            missingShards: missingShards,
            canReconstructLocally: canReconstruct,
            reconstructionPercentage: Double(localShards) / Double(cEcOriginalCount) * 100.0,
        )
    }

    /// Reconstruct data from local shards if possible
    /// - Parameters:
    ///   - erasureRoot: Erasure root identifying the data
    ///   - originalLength: Expected original data length
    /// - Returns: Reconstructed data
    public func reconstructFromLocalShards(erasureRoot: Data32, originalLength: Int) async throws -> Data {
        guard try await canReconstructLocally(erasureRoot: erasureRoot) else {
            let available = try await getLocalShardCount(erasureRoot: erasureRoot)
            throw ErasureCodingStoreError.insufficientShards(
                available: available,
                required: cEcOriginalCount,
            )
        }

        let availableIndices = try await getLocalShardIndices(erasureRoot: erasureRoot)
        let shards = try await getLocalShards(
            erasureRoot: erasureRoot,
            indices: Array(availableIndices.prefix(cEcOriginalCount)),
        )
        guard shards.count >= cEcOriginalCount else {
            throw ErasureCodingStoreError.insufficientShards(
                available: shards.count,
                required: cEcOriginalCount,
            )
        }

        return try await erasureCoding.reconstruct(shards: shards, originalLength: originalLength)
    }

    private func getLocalShardCount(erasureRoot: Data32) async throws -> Int {
        let indices = try await getLocalShardIndices(erasureRoot: erasureRoot)
        return indices.count
    }

    private func getLocalShardIndices(erasureRoot: Data32) async throws -> [UInt16] {
        let dataStoreIndices = try await dataStore.getAvailableShardIndices(erasureRoot: erasureRoot)
        let filesystemIndices = try await filesystemStore.getAvailableShardIndices(erasureRoot: erasureRoot)
        return Set(dataStoreIndices + filesystemIndices).sorted()
    }

    private func getLocalShards(erasureRoot: Data32, indices: [UInt16]) async throws -> [(index: UInt16, data: Data)] {
        let dataStoreShards = try await dataStore.getShards(erasureRoot: erasureRoot, shardIndices: indices)
        let dataStoreShardMap = Dictionary(uniqueKeysWithValues: dataStoreShards.map { ($0.index, $0.data) })

        var shards: [(index: UInt16, data: Data)] = []
        shards.reserveCapacity(indices.count)
        for index in indices {
            if let shard = dataStoreShardMap[index] {
                shards.append((index: index, data: shard))
            } else if let shard = try await filesystemStore.getD3LShard(erasureRoot: erasureRoot, shardIndex: index) {
                shards.append((index: index, data: shard))
            }
        }
        return shards
    }
}
