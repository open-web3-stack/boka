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
    ) async throws -> (BlockchainServices, GuaranteeingService) {
        let services = await BlockchainServices(
            config: config,
            timeProvider: MockTimeProvider(time: time),
            keysCount: keysCount
        )

        let guaranteeingService = await GuaranteeingService(
            config: config,
            eventBus: services.eventBus,
            scheduler: services.scheduler,
            dataProvider: services.dataProvider,
            keystore: services.keystore,
            dataStore: services.dataStore
        )
        return (services, guaranteeingService)
    }

    @Test func onGenesis() async throws {
        let (_, guaranteeingService) = try await setup(keysCount: 1)

        await guaranteeingService.onSyncCompleted()

        let publicKey = try DevKeyStore.getDevKey(seed: 0).ed25519
        let signingKey = guaranteeingService.signingKey.value!

        #expect(signingKey.0 == 0)
        #expect(signingKey.1.publicKey == publicKey)
    }

//    @Test func workPackagesReceived() async throws {
//        let (services, guaranteeingService) = try await setup(keysCount: 1)
//
//        await guaranteeingService.onSyncCompleted()
//
//        let workpackage = WorkPackage.dummy(config: services.config)
//        await services.eventBus
//            .publish(RuntimeEvents.WorkPackagesReceived(coreIndex: 0, workPackageRef: workpackage.asRef(), extrinsics: []))
//    }
}
