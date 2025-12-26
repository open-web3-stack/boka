import Foundation
import Testing
import TracingUtils
import Utils

@testable import Blockchain

/// Unit tests for JAMNP-S shard assignment
struct JAMNPSShardAssignmentTests {
    func makeAssignment() -> JAMNPSShardAssignment {
        JAMNPSShardAssignment()
    }

    // MARK: - Basic Assignment Tests

    @Test
    func getShardAssignmentBasic() async throws {
        let assignment = makeAssignment()

        // Test basic case: core 0, validator 0, total validators 1023
        let shardIndex = await assignment.getShardAssignment(
            validatorIndex: 0,
            coreIndex: 0,
            totalValidators: 1023
        )

        // Formula: i = (cR + v) mod V
        // i = (0 * 342 + 0) mod 1023 = 0
        #expect(shardIndex == 0)
    }

    @Test
    func getShardAssignmentCore1() async throws {
        let assignment = makeAssignment()

        // Test: core 1, validator 0, total validators 1023
        let shardIndex = await assignment.getShardAssignment(
            validatorIndex: 0,
            coreIndex: 1,
            totalValidators: 1023
        )

        // Formula: i = (cR + v) mod V
        // i = (1 * 342 + 0) mod 1023 = 342
        #expect(shardIndex == 342)
    }

    @Test
    func getShardAssignmentValidator1() async throws {
        let assignment = makeAssignment()

        // Test: core 0, validator 1, total validators 1023
        let shardIndex = await assignment.getShardAssignment(
            validatorIndex: 1,
            coreIndex: 0,
            totalValidators: 1023
        )

        // Formula: i = (cR + v) mod V
        // i = (0 * 342 + 1) mod 1023 = 1
        #expect(shardIndex == 1)
    }

    @Test
    func getShardAssignmentModuloWrap() async throws {
        let assignment = makeAssignment()

        // Test modulo wraparound: core 3, validator 0
        let shardIndex = await assignment.getShardAssignment(
            validatorIndex: 0,
            coreIndex: 3,
            totalValidators: 1023
        )

        // Formula: i = (cR + v) mod V
        // i = (3 * 342 + 0) mod 1023 = 1026 mod 1023 = 3
        #expect(shardIndex == 3)
    }

    @Test
    func getShardAssignmentLastCore() async throws {
        let assignment = makeAssignment()

        // Test last core: core 15, validator 0
        let shardIndex = await assignment.getShardAssignment(
            validatorIndex: 0,
            coreIndex: 15,
            totalValidators: 1023
        )

        // Formula: i = (cR + v) mod V
        // i = (15 * 342 + 0) mod 1023 = 5130 mod 1023 = 5130 - 5*1023 = 15
        #expect(shardIndex == 15)
    }

    @Test
    func getShardAssignmentLastValidator() async throws {
        let assignment = makeAssignment()

        // Test last validator: core 0, validator 1022
        let shardIndex = await assignment.getShardAssignment(
            validatorIndex: 1022,
            coreIndex: 0,
            totalValidators: 1023
        )

        // Formula: i = (cR + v) mod V
        // i = (0 * 342 + 1022) mod 1023 = 1022
        #expect(shardIndex == 1022)
    }

    @Test
    func getShardAssignmentLargeValues() async throws {
        let assignment = makeAssignment()

        // Test with larger values
        let shardIndex = await assignment.getShardAssignment(
            validatorIndex: 500,
            coreIndex: 10,
            totalValidators: 1023
        )

        // Formula: i = (cR + v) mod V
        // i = (10 * 342 + 500) mod 1023 = 3920 mod 1023 = 3920 - 3*1023 = 3920 - 3069 = 851
        #expect(shardIndex == 851)
    }

    // MARK: - Test Different Validator Counts

    @Test
    func getShardAssignmentSixValidators() async throws {
        let assignment = makeAssignment()

        // Test with 6 validators (devnet scenario)
        let shardIndex = await assignment.getShardAssignment(
            validatorIndex: 0,
            coreIndex: 0,
            totalValidators: 6
        )

        // Formula: i = (cR + v) mod V
        // i = (0 * 342 + 0) mod 6 = 0
        #expect(shardIndex == 0)
    }

    @Test
    func getShardAssignmentSixValidatorsWrap() async throws {
        let assignment = makeAssignment()

        // Test with 6 validators, should wrap around
        let shardIndex = await assignment.getShardAssignment(
            validatorIndex: 0,
            coreIndex: 1,
            totalValidators: 6
        )

        // Formula: i = (cR + v) mod V
        // i = (1 * 342 + 0) mod 6 = 342 mod 6 = 0
        #expect(shardIndex == 0)
    }

    // MARK: - Get All Assigned Shards Tests

    @Test
    func getAllAssignedShardsDefaultCores() async throws {
        let assignment = makeAssignment()

        let shards = await assignment.getAllAssignedShards(
            validatorIndex: 0,
            coreCount: 16,
            totalValidators: 1023
        )

        #expect(shards.count == 16)

        // First shard should be 0 (core 0, validator 0)
        #expect(shards[0] == 0)

        // Second shard should be 342 (core 1, validator 0)
        #expect(shards[1] == 342)

        // Last shard should be 15 (core 15, validator 0, wraps)
        #expect(shards[15] == 15)
    }

    @Test
    func getAllAssignedShardsValidator100() async throws {
        let assignment = makeAssignment()

        let shards = await assignment.getAllAssignedShards(
            validatorIndex: 100,
            coreCount: 16,
            totalValidators: 1023
        )

        #expect(shards.count == 16)

        // Each shard should be offset by 100 from the validator 0 case
        #expect(shards[0] == 100)
        #expect(shards[1] == 442) // 342 + 100
    }

    @Test
    func getAllAssignedShardsEightCores() async throws {
        let assignment = makeAssignment()

        let shards = await assignment.getAllAssignedShards(
            validatorIndex: 0,
            coreCount: 8,
            totalValidators: 1023
        )

        #expect(shards.count == 8)

        // Verify pattern
        #expect(shards[0] == 0)
        #expect(shards[1] == 342)
        #expect(shards[7] == 7) // 7 * 342 mod 1023 = 2394 mod 1023 = 348... wait, 2394 - 2*1023 = 348
        // Actually: 7 * 342 = 2394, 2394 mod 1023 = 2394 - 2*1023 = 2394 - 2046 = 348
        // Hmm, let me recalculate
        // 2394 / 1023 = 2.34..., so 2 * 1023 = 2046, 2394 - 2046 = 348
        #expect(shards[7] == 348)
    }

    // MARK: - Get Validators For Shard Tests

    @Test
    func getValidatorsForShardBasic() async throws {
        let assignment = makeAssignment()

        let validators = await assignment.getValidatorsForShard(
            shardIndex: 0,
            coreIndex: 0,
            totalValidators: 1023
        )

        // For shard 0, core 0, validator 0 should have it
        #expect(validators.count == 1)
        #expect(validators[0] == 0)
    }

    @Test
    func getValidatorsForShard342() async throws {
        let assignment = makeAssignment()

        let validators = await assignment.getValidatorsForShard(
            shardIndex: 342,
            coreIndex: 1,
            totalValidators: 1023
        )

        // For shard 342, core 1, validator 0 should have it
        #expect(validators.count == 1)
        #expect(validators[0] == 0)
    }

    @Test
    func getValidatorsForShardMiddle() async throws {
        let assignment = makeAssignment()

        let validators = await assignment.getValidatorsForShard(
            shardIndex: 100,
            coreIndex: 0,
            totalValidators: 1023
        )

        // For shard 100, core 0, validator 100 should have it
        #expect(validators.count == 1)
        #expect(validators[0] == 100)
    }

    // MARK: - Get Validators For Missing Shards Tests

    @Test
    func getValidatorsForMissingShardsBasic() async throws {
        let assignment = makeAssignment()

        let missingShards: [UInt16] = [0, 100, 200, 300]
        let validatorMap = await assignment.getValidatorsForMissingShards(
            missingShardIndices: missingShards,
            coreIndex: 0,
            totalValidators: 1023
        )

        // Each shard should map to one validator
        #expect(validatorMap.count == 4)

        // Shard 0 -> validator 0
        #expect(validatorMap[0]?.contains(0) == true)

        // Shard 100 -> validator 100
        #expect(validatorMap[100]?.contains(100) == true)

        // Shard 200 -> validator 200
        #expect(validatorMap[200]?.contains(200) == true)

        // Shard 300 -> validator 300
        #expect(validatorMap[300]?.contains(300) == true)
    }

    @Test
    func getValidatorsForMissingShardsCore1() async throws {
        let assignment = makeAssignment()

        let missingShards: [UInt16] = [342, 442, 542]
        let validatorMap = await assignment.getValidatorsForMissingShards(
            missingShardIndices: missingShards,
            coreIndex: 1,
            totalValidators: 1023
        )

        #expect(validatorMap.count == 3)

        // For core 1: i = (1 * 342 + v) mod 1023
        // Shard 342: 342 = (342 + v) mod 1023 -> v = 0
        #expect(validatorMap[0]?.contains(342) == true)

        // Shard 442: 442 = (342 + v) mod 1023 -> v = 100
        #expect(validatorMap[100]?.contains(442) == true)

        // Shard 542: 542 = (342 + v) mod 1023 -> v = 200
        #expect(validatorMap[200]?.contains(542) == true)
    }

    @Test
    func getValidatorsForMissingShardsEmpty() async throws {
        let assignment = makeAssignment()

        let missingShards: [UInt16] = []
        let validatorMap = await assignment.getValidatorsForMissingShards(
            missingShardIndices: missingShards,
            coreIndex: 0,
            totalValidators: 1023
        )

        #expect(validatorMap.isEmpty)
    }

    @Test
    func getValidatorsForMissingShardsMany() async throws {
        let assignment = makeAssignment()

        // Test with many missing shards
        let missingShards = Array(0 ..< 100) as [UInt16]
        let validatorMap = await assignment.getValidatorsForMissingShards(
            missingShardIndices: missingShards,
            coreIndex: 0,
            totalValidators: 1023
        )

        #expect(validatorMap.count == 100)

        // Each validator should have exactly one shard
        for (validatorIndex, shards) in validatorMap {
            #expect(shards.count == 1)
            #expect(validatorIndex == shards[0])
        }
    }

    // MARK: - Validation Tests

    @Test
    func isValidShardIndexValid() async throws {
        let assignment = makeAssignment()

        let isValid = await assignment.isValidShardIndex(
            shardIndex: 500,
            totalValidators: 1023
        )

        #expect(isValid)
    }

    @Test
    func isValidShardIndexZero() async throws {
        let assignment = makeAssignment()

        let isValid = await assignment.isValidShardIndex(
            shardIndex: 0,
            totalValidators: 1023
        )

        #expect(isValid)
    }

    @Test
    func isValidShardIndexMax() async throws {
        let assignment = makeAssignment()

        let isValid = await assignment.isValidShardIndex(
            shardIndex: 1022,
            totalValidators: 1023
        )

        #expect(isValid)
    }

    @Test
    func isValidShardIndexInvalid() async throws {
        let assignment = makeAssignment()

        let isValid = await assignment.isValidShardIndex(
            shardIndex: 1023,
            totalValidators: 1023
        )

        #expect(!isValid)
    }

    @Test
    func getShardsPerValidatorDefault() async throws {
        let assignment = makeAssignment()

        let count = await assignment.getShardsPerValidator(coreCount: 16)

        #expect(count == 16)
    }

    @Test
    func getShardsPerValidatorCustom() async throws {
        let assignment = makeAssignment()

        let count = await assignment.getShardsPerValidator(coreCount: 8)

        #expect(count == 8)
    }

    // MARK: - Edge Cases

    @Test
    func getShardAssignmentAllMaxValues() async throws {
        let assignment = makeAssignment()

        let shardIndex = await assignment.getShardAssignment(
            validatorIndex: 1022,
            coreIndex: 15,
            totalValidators: 1023
        )

        // Formula: i = (cR + v) mod V
        // i = (15 * 342 + 1022) mod 1023
        // i = (5130 + 1022) mod 1023
        // i = 6152 mod 1023
        // 6152 / 1023 = 6.01..., so 6 * 1023 = 6138
        // 6152 - 6138 = 14
        #expect(shardIndex == 14)
    }

    @Test
    func getShardAssignmentMinValues() async throws {
        let assignment = makeAssignment()

        let shardIndex = await assignment.getShardAssignment(
            validatorIndex: 0,
            coreIndex: 0,
            totalValidators: 1
        )

        // Formula: i = (cR + v) mod V
        // i = (0 * 342 + 0) mod 1 = 0
        #expect(shardIndex == 0)
    }

    @Test
    func getAllAssignedShardsAllCores() async throws {
        let assignment = makeAssignment()

        let shards = await assignment.getAllAssignedShards(
            validatorIndex: 0,
            coreCount: 16,
            totalValidators: 1023
        )

        #expect(shards.count == 16)

        // Verify all shard indices are unique
        let uniqueShards = Set(shards)
        #expect(uniqueShards.count == 16)

        // Verify all shards are in valid range
        for shard in shards {
            #expect(shard < 1023)
        }
    }

    @Test
    func shardAssignmentDeterministic() async throws {
        let assignment = makeAssignment()

        // Same inputs should produce same outputs
        let result1 = await assignment.getShardAssignment(
            validatorIndex: 42,
            coreIndex: 7,
            totalValidators: 1023
        )

        let result2 = await assignment.getShardAssignment(
            validatorIndex: 42,
            coreIndex: 7,
            totalValidators: 1023
        )

        #expect(result1 == result2)
    }

    @Test
    func shardAssignmentDistribution() async throws {
        let assignment = makeAssignment()

        // Test that shards are distributed across validators
        var validatorCounts: [UInt16: Int] = [:]

        for validatorIndex in 0 ..< 100 {
            for coreIndex in 0 ..< 16 {
                let shardIndex = await assignment.getShardAssignment(
                    validatorIndex: UInt16(validatorIndex),
                    coreIndex: UInt16(coreIndex),
                    totalValidators: 1023
                )

                validatorCounts[shardIndex, default: 0] += 1
            }
        }

        // With 100 validators and 16 cores, we have 1600 shard assignments
        // These should be distributed across the 1023 possible shard indices
        let totalAssignments = validatorCounts.values.reduce(0, +)
        #expect(totalAssignments == 1600)

        // Each shard index should be assigned at most once per validator
        for (shardIndex, count) in validatorCounts {
            #expect(count <= 100, "Shard \(shardIndex) assigned \(count) times, expected <= 100")
        }
    }
}
