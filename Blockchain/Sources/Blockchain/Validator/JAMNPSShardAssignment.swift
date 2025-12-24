import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "JAMNPSShardAssignment")

/// JAMNP-S shard assignment utilities
///
/// Implements the shard assignment formula from JAMNP-S specification:
/// i = (cR + v) mod V
///
/// Where:
/// - v = validator index
/// - i = assigned shard index
/// - c = core index (0-15)
/// - R = recovery threshold (342)
/// - V = number of validators (1023)
public actor JAMNPSShardAssignment {
    /// Recovery threshold (R)
    private let recoveryThreshold: UInt32 = 342

    /// Total number of validators (V) in mainnet
    private let mainnetValidatorCount: UInt32 = 1023

    /// Calculate the shard index assigned to a validator for a given core
    ///
    /// Per JAMNP-S spec: i = (cR + v) mod V
    ///
    /// - Parameters:
    ///   - validatorIndex: Index of the validator (v)
    ///   - coreIndex: Index of the core (c)
    ///   - totalValidators: Total number of validators (V)
    /// - Returns: Assigned shard index (i)
    public func getShardAssignment(
        validatorIndex: UInt16,
        coreIndex: UInt16,
        totalValidators: UInt16
    ) -> UInt16 {
        let c = UInt32(coreIndex)
        let v = UInt32(validatorIndex)
        let V = UInt32(totalValidators)
        let R = recoveryThreshold

        let shardIndex = (c * R + v) % V

        logger.trace(
            """
            Shard assignment: validator=\(validatorIndex), core=\(coreIndex), \
            total=\(totalValidators) -> shard=\(shardIndex)
            """
        )

        return UInt16(shardIndex)
    }

    /// Get all shard indices assigned to a validator across all cores
    ///
    /// - Parameters:
    ///   - validatorIndex: Index of the validator
    ///   - coreCount: Number of cores (default: 16)
    ///   - totalValidators: Total number of validators
    /// - Returns: Array of assigned shard indices (one per core)
    public func getAllAssignedShards(
        validatorIndex: UInt16,
        coreCount: UInt16 = 16,
        totalValidators: UInt16
    ) -> [UInt16] {
        var shards: [UInt16] = []

        for coreIndex in 0 ..< coreCount {
            let shardIndex = getShardAssignment(
                validatorIndex: validatorIndex,
                coreIndex: coreIndex,
                totalValidators: totalValidators
            )
            shards.append(shardIndex)
        }

        return shards
    }

    /// Get validators that should hold a specific shard for a given core
    ///
    /// This is useful for determining which validators to query when fetching shards.
    /// Since the assignment function is not one-to-one, multiple validators may have
    /// overlapping shard assignments.
    ///
    /// - Parameters:
    ///   - shardIndex: The shard index to look up
    ///   - coreIndex: The core index
    ///   - totalValidators: Total number of validators
    /// - Returns: Array of validator indices that should hold this shard
    public func getValidatorsForShard(
        shardIndex: UInt16,
        coreIndex: UInt16,
        totalValidators: UInt16
    ) -> [UInt16] {
        let targetShardIndex = UInt32(shardIndex)
        let c = UInt32(coreIndex)
        let V = UInt32(totalValidators)
        let R = recoveryThreshold

        var validators: [UInt16] = []

        // Solve: targetShardIndex = (c * R + v) mod V
        // for v in range 0..<V
        //
        // This gives us: v = (targetShardIndex - c * R) mod V
        // But there may be multiple solutions due to modulo
        //
        // We need to find all v such that (c * R + v) % V == targetShardIndex
        // This is equivalent to: v % V == (targetShardIndex - c * R) % V
        // So: v = (targetShardIndex - c * R + k * V) for k = 0, 1, 2, ...

        let base = (targetShardIndex - c * R) % V

        // Since v must be in range 0..<V, we only need k=0
        let v = base < 0 ? base + V : base

        if v < V {
            validators.append(UInt16(v))
        }

        // In practice, for each core/shard combination, there's exactly one validator
        // However, a validator holds multiple shards (one per core)

        logger.trace(
            """
            Validators for shard=\(shardIndex), core=\(coreIndex), \
            total=\(totalValidators) -> \(validators.count) validators
            """
        )

        return validators
    }

    /// Calculate which validators to query for a set of shards
    ///
    /// This is useful for fetching shards when you have missing shard indices.
    /// Returns a mapping of validator index to shards they should have.
    ///
    /// - Parameters:
    ///   - missingShardIndices: Array of shard indices that are needed
    ///   - coreIndex: The core index
    ///   - totalValidators: Total number of validators
    /// - Returns: Dictionary mapping validator indices to their assigned shard indices
    public func getValidatorsForMissingShards(
        missingShardIndices: [UInt16],
        coreIndex: UInt16,
        totalValidators: UInt16
    ) -> [UInt16: [UInt16]] {
        var validatorToShards: [UInt16: [UInt16]] = [:]

        for shardIndex in missingShardIndices {
            // Invert the assignment to find which validator should have this shard
            // i = (c * R + v) % V
            // v = (i - c * R) % V

            let i = UInt32(shardIndex)
            let c = UInt32(coreIndex)
            let V = UInt32(totalValidators)
            let R = recoveryThreshold

            var v = (i - c * R) % V
            if v < 0 {
                v += V
            }

            let validatorIndex = UInt16(v)

            if validatorToShards[validatorIndex] == nil {
                validatorToShards[validatorIndex] = []
            }
            validatorToShards[validatorIndex]?.append(shardIndex)
        }

        logger.debug(
            """
            Mapped \(missingShardIndices.count) missing shards to \
            \(validatorToShards.count) validators
            """
        )

        return validatorToShards
    }

    /// Validate that a shard index is within valid range
    ///
    /// - Parameters:
    ///   - shardIndex: The shard index to validate
    ///   - totalValidators: Total number of validators
    /// - Returns: True if shard index is valid
    public func isValidShardIndex(shardIndex: UInt16, totalValidators: UInt16) -> Bool {
        shardIndex < totalValidators
    }

    /// Get the expected number of shards per validator
    ///
    /// Each validator gets one shard per core.
    ///
    /// - Parameters:
    ///   - coreCount: Number of cores
    /// - Returns: Number of shards assigned to each validator
    public func getShardsPerValidator(coreCount: UInt16 = 16) -> Int {
        Int(coreCount)
    }
}
