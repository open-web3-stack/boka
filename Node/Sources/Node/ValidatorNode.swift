import Blockchain
import TracingUtils
import Utils

public class ValidatorNode: Node {
    private var validator: Validator!

    public required init(
        genesis: Genesis, config: Config, eventBus: EventBus, keystore: KeyStore
    ) async throws {
        try await super.init(genesis: genesis, config: config, eventBus: eventBus)
        validator = await Validator(
            blockchain: blockchain,
            keystore: keystore,
            eventBus: eventBus,
            timeProvider: timeProvider
        )

        let genesisState = try await blockchain.getState(hash: Data32())

        await validator.on(genesis: genesisState!)
    }
}
