import Blockchain
import Foundation
import TracingUtils
import Utils

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
            dataProvider: dataProvider
        )
        self.validator = validator

        let syncManager = network.syncManager
        let dataProvider: BlockchainDataProvider = blockchain.dataProvider
        let local = config.local
        Task {
            let genesisState = try await dataProvider.getState(hash: dataProvider.genesisBlockHash)
            if !local {
                await syncManager.waitForSyncCompletion()
            }
            await validator.onSyncCompleted()
            if await dataProvider.bestHead.hash == dataProvider.genesisBlockHash {
                await validator.on(genesis: genesisState)
            }
        }
    }
}
