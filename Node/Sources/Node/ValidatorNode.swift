import Blockchain
import TracingUtils
import Utils

public class ValidatorNode: Node {
    private var validator: Validator!

    public required init(
        genesis: Genesis, config: Config, eventBus: EventBus, keystore: KeyStore
    ) async throws {
        try await super.init(genesis: genesis, config: config, eventBus: eventBus)

        let timeProvider = SystemTimeProvider(slotPeriodSeconds: config.value.slotPeriodSeconds)
        let scheduler = DispatchQueueScheduler(
            timeslotPeriod: UInt32(config.value.slotPeriodSeconds),
            timeProvider: timeProvider
        )
        validator = await Validator(
            blockchain: blockchain,
            keystore: keystore,
            eventBus: eventBus,
            scheduler: scheduler
        )

        let genesisState = try await blockchain.getState(hash: Data32())

        await validator.on(genesis: genesisState!)
    }
}
