import Blockchain
import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "ValidatorNode")

public class ValidatorNode: Node {
    private var validator: ValidatorService!

    public required init(
        config: Config,
        genesis: Genesis,
        eventBus: EventBus,
        keystore: KeyStore,
        scheduler: Scheduler = DispatchQueueScheduler(timeProvider: SystemTimeProvider())
    ) async throws {
        try await super.init(
            config: config,
            genesis: genesis,
            eventBus: eventBus,
            keystore: keystore,
            scheduler: scheduler
        )

        let validator = await ValidatorService(
            blockchain: blockchain,
            keystore: keystore,
            eventBus: eventBus,
            scheduler: scheduler,
            dataProvider: dataProvider,
            dataStore: config.dataStore.create()
        )
        self.validator = validator

        let syncManager = network.syncManager
        let dataProvider = dataProvider
        let local = config.local
        Task {
            if !local {
                logger.trace("Waiting for sync")
                await syncManager.waitForSyncCompletion()
            }
            logger.trace("Sync completed")
            await validator.onSyncCompleted()
            let genesisState = try await dataProvider.getState(hash: dataProvider.genesisBlockHash)
            if await dataProvider.bestHead.hash == dataProvider.genesisBlockHash {
                logger.trace("Calling on(genesis:)")
                await validator.on(genesis: genesisState)
            }
        }
    }
}
