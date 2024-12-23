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

        let extrinsicPoolService = await ExtrinsicPoolService(
            config: config,
            dataProvider: services.dataProvider,
            eventBus: services.eventBus
        )

        let runtime = Runtime(config: config)

        let guaranteeingService = await GuaranteeingService(
            config: config,
            eventBus: services.eventBus,
            scheduler: services.scheduler,
            dataProvider: services.dataProvider,
            keystore: services.keystore,
            runtime: runtime,
            extrinsicPool: extrinsicPoolService,
            dataStore: services.dataStore
        )
        return (services, guaranteeingService)
    }

    @Test func onGenesis() async throws {
        let (services, validatorService) = try await setup()
        let genesisState = services.genesisState
        let storeMiddleware = services.storeMiddleware
        let scheduler = services.scheduler

        await validatorService.on(genesis: genesisState)

        let events = await storeMiddleware.wait()

        // Check if xxx events were published

        // Check if block author tasks were scheduled
        #expect(scheduler.taskCount == 1)
    }
}
