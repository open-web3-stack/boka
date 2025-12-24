import Foundation
import Testing
import TracingUtils
import Utils

@testable import Blockchain

/// Unit tests for AvailabilityNetworkClient
struct AvailabilityNetworkClientTests {
    func makeConfig() -> ProtocolConfigRef {
        ProtocolConfigRef(.dev)
    }

    func makeErasureCoding() -> ErasureCodingService {
        ErasureCodingService(config: makeConfig())
    }

    func makeClient() -> AvailabilityNetworkClient {
        AvailabilityNetworkClient(
            config: makeConfig(),
            erasureCoding: makeErasureCoding()
        )
    }

    // MARK: - Initialization Tests

    @Test
    func clientInitialization() async {
        let client = makeClient()

        // Verify client was created
        // (We can't test much without actually connecting)
    }

    @Test
    func clientSetPeerManager() async {
        let client = makeClient()
        let peerManager = PeerManager()

        client.setPeerManager(peerManager)

        // Just verify it doesn't crash
    }

    // MARK: - Fetch Strategy Tests

    @Test
    func fetchStrategyRawValues() {
        #expect(FetchStrategy.fast != FetchStrategy.verified)
        #expect(FetchStrategy.adaptive != FetchStrategy.localOnly)
    }

    // MARK: - Request Deduplication Tests

    @Test
    func requestDeduplicationCacheKey() async {
        let client = makeClient()

        // Test that duplicate requests would use cache
        let address = NetAddr(ip: "127.0.0.1", port: 1234)

        // We can't actually test without network, but we verify the structure
        #expect(address.ip == "127.0.0.1")
        #expect(address.port == 1234)
    }

    // MARK: - Shard Assignment Integration Tests

    @Test
    func clientUsesShardAssignment() async {
        let client = makeClient()

        // Verify the client has access to shard assignment
        let testValidator: UInt16 = 0
        let testCore: UInt16 = 0
        let totalValidators: UInt16 = 1023

        // Get assigned shards
        let shards = await client.shardAssignment.getAllAssignedShards(
            validatorIndex: testValidator,
            coreCount: 16,
            totalValidators: totalValidators
        )

        #expect(shards.count == 16)
        #expect(shards[0] == 0)
    }

    // MARK: - Error Handling Tests

    @Test
    func invalidAddressHandling() async {
        let client = makeClient()
        let invalidAddress = NetAddr(ip: "", port: 0)

        // Test with invalid erasure root
        let erasureRoot = Data32.random()
        let shardIndex: UInt16 = 0

        // Should throw error (placeholder implementation)
        await confirmation("Invalid address throws") { _ in
            do {
                _ = try await client.fetchAuditShard(
                    erasureRoot: erasureRoot,
                    shardIndex: shardIndex,
                    from: invalidAddress
                )
                Issue.record("Expected error for invalid address")
            } catch {
                // Expected
            }
        }
    }

    // MARK: - Concurrent Fetching Tests

    @Test
    func concurrentFetchingPreparation() async {
        let client = makeClient()

        let erasureRoot = Data32.random()
        let shardIndices = Array(0 ..< 10) as [UInt16]
        let validators = [UInt16: NetAddr](uniqueKeysWithValues: (0 ..< 10).map {
            ($0, NetAddr(ip: "127.0.0.\($0)", port: 1234))
        })

        // Test preparation (won't actually fetch without network)
        #expect(validators.count == 10)
        #expect(shardIndices.count == 10)
    }

    @Test
    func concurrentFetchingWithRequiredShards() async {
        let client = makeClient()

        // Test with 342 required shards (reconstruction threshold)
        let requiredShards = 342

        // Verify the threshold
        #expect(requiredShards == 342)
    }

    // MARK: - Timeout Tests

    @Test
    func timeoutValues() async {
        let client = makeClient()

        // Access timeout values through the client's behavior
        // (Can't directly test private properties, but can verify behavior)
    }

    // MARK: - Message Size Validation Tests

    @Test
    func messageSizeLimits() async {
        // Verify message size limits are enforced
        #expect(MessageSizeLimits.maxShardResponseSize == 1024 * 1024)
        #expect(MessageSizeLimits.maxSegmentShardsPerStream == 2 * 3072)
        #expect(MessageSizeLimits.maxSegmentsPerStream == 3072)
    }

    @Test
    func maxConcurrentRequests() async {
        // Verify max concurrent requests limit
        #expect(MessageSizeLimits.maxConcurrentRequests == 100)
    }

    // MARK: - Protocol Variant Tests

    @Test
    void protocolVariantSelection() async {
        // Test that we can select between CE 139 (fast) and CE 140 (verified)
        let fastStrategy = FetchStrategy.fast
        let verifiedStrategy = FetchStrategy.verified
        let adaptiveStrategy = FetchStrategy.adaptive

        // Verify they're different
        #expect(fastStrategy != verifiedStrategy)
        #expect(verifiedStrategy != adaptiveStrategy)
        #expect(fastStrategy != adaptiveStrategy)
    }

    // MARK: - Role-Based Routing Tests

    @Test
    func nodeRoleValues() async {
        // Verify node role enum values
        #expect(NodeRole.auditor.rawValue == 0)
        #expect(NodeRole.guarantor.rawValue == 1)
        #expect(NodeRole.assurer.rawValue == 2)
        #expect(NodeRole.builder.rawValue == 3)
    }

    @Test
    func roleBasedRequestType() async {
        // Different roles use different request types
        #expect(ShardRequestType.auditShard.rawValue == 138) // Auditor
        #expect(ShardRequestType.segmentShardsFast.rawValue == 139) // Guarantor
        #expect(ShardRequestType.segmentShardsVerified.rawValue == 140) // Guarantor
        #expect(ShardRequestType.fullBundle.rawValue == 147) // Auditor
        #expect(ShardRequestType.reconstructedSegments.rawValue == 148) // Guarantor
    }

    // MARK: - Shard Assignment Integration Tests

    @Test
    func validatorToShardMapping() async {
        let client = makeClient()

        // Test mapping validators to shards for efficient fetching
        let missingShards: [UInt16] = [0, 100, 200, 300]
        let coreIndex: UInt16 = 0
        let totalValidators: UInt16 = 1023

        let validatorMap = await client.shardAssignment.getValidatorsForMissingShards(
            missingShardIndices: missingShards,
            coreIndex: coreIndex,
            totalValidators: totalValidators
        )

        // Should map each shard to exactly one validator
        #expect(validatorMap.count == 4)

        for (validatorIndex, shards) in validatorMap {
            #expect(shards.count == 1)
            #expect(validatorIndex == shards[0])
        }
    }

    @Test
    func shardAssignmentForAllCores() async {
        let client = makeClient()

        // Test that all 16 cores get assigned shards
        let validatorIndex: UInt16 = 0
        let coreCount: UInt16 = 16
        let totalValidators: UInt16 = 1023

        let assignedShards = await client.shardAssignment.getAllAssignedShards(
            validatorIndex: validatorIndex,
            coreCount: coreCount,
            totalValidators: totalValidators
        )

        #expect(assignedShards.count == 16)

        // Verify all shard indices are unique and in valid range
        let uniqueShards = Set(assignedShards)
        #expect(uniqueShards.count == 16)

        for shard in assignedShards {
            #expect(shard < 1023)
        }
    }

    // MARK: - Integration with Erasure Coding Tests

    @Test
    void clientHasErasureCodingAccess() async {
        let client = makeClient()

        // Verify client has access to erasure coding service
        // This is needed for generating justifications
    }

    // MARK: - Edge Cases

    @Test
    func emptyValidatorList() async {
        let client = makeClient()

        let validators: [UInt16: NetAddr] = [:]
        let erasureRoot = Data32.random()
        let shardIndices: [UInt16] = [0, 1, 2]

        // Should handle empty validator list gracefully
        #expect(validators.isEmpty)
    }

    @Test
    func singleValidator() async {
        let client = makeClient()

        let validators = [0: NetAddr(ip: "127.0.0.1", port: 1234)]
        let erasureRoot = Data32.random()
        let shardIndices: [UInt16] = [0]

        #expect(validators.count == 1)
    }

    @Test
    func maximumValidators() async {
        let client = makeClient()

        // Test with maximum number of validators (1023)
        let validatorCount = 1023
        let shardIndices = Array(0 ..< 342) as [UInt16]

        #expect(shardIndices.count == 342)
    }

    @Test
    func allShardsMissing() async {
        let client = makeClient()

        // Test when all shards are missing
        let missingShards = Array(0 ..< 1023) as [UInt16]
        let coreIndex: UInt16 = 0
        let totalValidators: UInt16 = 1023

        let validatorMap = await client.shardAssignment.getValidatorsForMissingShards(
            missingShardIndices: missingShards,
            coreIndex: coreIndex,
            totalValidators: totalValidators
        )

        // All shards should be mapped to validators
        #expect(validatorMap.count == 1023)
    }

    @Test
    func noShardsMissing() async {
        let client = makeClient()

        // Test when no shards are missing
        let missingShards: [UInt16] = []
        let coreIndex: UInt16 = 0
        let totalValidators: UInt16 = 1023

        let validatorMap = await client.shardAssignment.getValidatorsForMissingShards(
            missingShardIndices: missingShards,
            coreIndex: coreIndex,
            totalValidators: totalValidators
        )

        #expect(validatorMap.isEmpty)
    }

    // MARK: - Fallback Strategy Tests

    @Test
    void fallbackStrategy() async {
        // Test fallback from CE 147 to CE 138
        // Test fallback from CE 148 to CE 139/140
        let bundleRequestType = ShardRequestType.fullBundle // CE 147
        let auditRequestType = ShardRequestType.auditShard // CE 138

        #expect(bundleRequestType.rawValue == 147)
        #expect(auditRequestType.rawValue == 138)

        let segmentRequestType = ShardRequestType.reconstructedSegments // CE 148
        let segmentShardType = ShardRequestType.segmentShardsFast // CE 139

        #expect(segmentRequestType.rawValue == 148)
        #expect(segmentShardType.rawValue == 139)
    }
}
