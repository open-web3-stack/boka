import Foundation
import Testing
import TracingUtils
import Utils

@testable import Blockchain

struct GuaranteeingServiceTests {
    func setup(
        config: ProtocolConfigRef = .dev,
        time: TimeInterval = 988,
        keysCount: Int = 12
    ) async throws -> BlockchainServices {
        await BlockchainServices(
            config: config,
            timeProvider: MockTimeProvider(time: time),
            keysCount: keysCount
        )
    }

    @Test func onGenesis() async throws {
        let services = try await setup(keysCount: 1)
        let guaranteeingService = await services.guaranteeingService

        let publicKey = try DevKeyStore.getDevKey(seed: 0).ed25519
        let signingKey = guaranteeingService.signingKey.value!

        #expect(signingKey.0 == 0)
        #expect(signingKey.1.publicKey == publicKey)
    }
}
