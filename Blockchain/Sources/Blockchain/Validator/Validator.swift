import Foundation
import Utils

public class Validator {
    private let blockchain: Blockchain
    private var keystore: KeyStore
    private let scheduler: Scheduler
    private let safrole: SafroleService
    private let extrinsicPool: ExtrinsicPoolService
    private let blockAuthor: BlockAuthor

    public init(
        blockchain: Blockchain,
        keystore: KeyStore,
        eventBus: EventBus,
        timeProvider: TimeProvider
    ) async {
        self.blockchain = blockchain
        self.keystore = keystore

        scheduler = Scheduler(timeslotPeriod: UInt32(blockchain.config.value.slotPeriodSeconds), offset: Date.jamCommonEraBeginning)

        safrole = await SafroleService(
            config: blockchain.config,
            eventBus: eventBus,
            keystore: keystore
        )

        extrinsicPool = await ExtrinsicPoolService(
            blockchain: blockchain,
            eventBus: eventBus
        )

        blockAuthor = await BlockAuthor(
            blockchain: blockchain,
            eventBus: eventBus,
            keystore: keystore,
            timeProvider: timeProvider,
            scheduler: scheduler,
            extrinsicPool: extrinsicPool
        )
    }

    public func on(genesis: StateRef) async {
        await safrole.on(genesis: genesis)
    }
}
