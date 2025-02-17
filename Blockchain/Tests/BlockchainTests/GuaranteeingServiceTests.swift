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

        let SafroleTicketPoolService = await SafroleTicketPoolService(
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
            safroleTicketPool: SafroleTicketPoolService,
            dataStore: services.dataStore
        )
        return (services, guaranteeingService)
    }

    @Test func onGenesis() async throws {
        let (services, validatorService) = try await setup()
        let genesisState = services.genesisState
        let storeMiddleware = services.storeMiddleware
        let scheduler = services.scheduler

        var allWorkPackages = [WorkPackage]()
        for _ in 0 ..< services.config.value.totalNumberOfCores {
            let workpackage = WorkPackage(
                authorizationToken: Data(),
                authorizationServiceIndex: 0,
                authorizationCodeHash: Data32.random(),
                parameterizationBlob: Data(),
                context: RefinementContext.dummy(config: services.config),
                workItems: try! ConfigLimitedSizeArray(config: services.config, defaultValue: WorkItem.dummy(config: services.config))
            )
            allWorkPackages.append(workpackage)
        }
        await services.eventBus.publish(RuntimeEvents.WorkPackagesGenerated(items: allWorkPackages))
        await validatorService.on(genesis: genesisState)
        await storeMiddleware.wait()
        #expect(scheduler.taskCount == 1)
    }
}
