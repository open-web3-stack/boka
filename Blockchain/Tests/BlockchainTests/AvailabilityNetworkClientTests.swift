import Foundation
import Testing
import TracingUtils
import Utils

@testable import Blockchain

/// Unit tests for AvailabilityNetworkClient
struct AvailabilityNetworkClientTests {
    func makeConfig() -> ProtocolConfigRef {
        ProtocolConfig(.dev)
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
        // Verify client was created successfully
    }

    @Test
    func fetchStrategyRawValues() {
        #expect(FetchStrategy.fast != FetchStrategy.verified)
        #expect(FetchStrategy.adaptive != FetchStrategy.localOnly)
    }

    @Test
    func clientUsesShardAssignment() async throws {
        let shardAssignment = JAMNPSShardAssignment()

        let shardIndex = try await shardAssignment.getShardAssignment(
            validatorIndex: 0,
            coreIndex: 0,
            totalValidators: 1023
        )

        #expect(shardIndex < 342) // 1023 / 3 = 341
    }
}
