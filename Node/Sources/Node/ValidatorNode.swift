import Blockchain
import Foundation
import TracingUtils
import Utils

public class ValidatorNode: Node {
    private var validator: ValidatorService!

    override public required init(
        config: Config, genesis: Genesis, eventBus: EventBus, keystore: KeyStore
    ) async throws {
        try await super.init(config: config, genesis: genesis, eventBus: eventBus, keystore: keystore)

        let scheduler = DispatchQueueScheduler(timeProvider: timeProvider)
        validator = await ValidatorService(
            blockchain: blockchain,
            keystore: keystore,
            eventBus: eventBus,
            scheduler: scheduler,
            dataProvider: dataProvider
        )

        let genesisState = try await dataProvider.getState(hash: blockchain.dataProvider.genesisBlockHash)

        await validator.on(genesis: genesisState)
    }
}
