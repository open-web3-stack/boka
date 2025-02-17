import Foundation
import Utils

public final class ValidatorService: Sendable {
    private let blockchain: Blockchain
    private let keystore: KeyStore
    private let safrole: SafroleService
    private let safroleTicketPool: SafroleTicketPoolService
    private let blockAuthor: BlockAuthor
    private let dataAvailability: DataAvailability

    public init(
        blockchain: Blockchain,
        keystore: KeyStore,
        eventBus: EventBus,
        scheduler: Scheduler,
        dataProvider: BlockchainDataProvider,
        dataStore: DataStore
    ) async {
        self.blockchain = blockchain
        self.keystore = keystore

        safrole = await SafroleService(
            config: blockchain.config,
            eventBus: eventBus,
            keystore: keystore
        )

        safroleTicketPool = await SafroleTicketPoolService(
            config: blockchain.config,
            dataProvider: dataProvider,
            eventBus: eventBus
        )

        blockAuthor = await BlockAuthor(
            config: blockchain.config,
            dataProvider: dataProvider,
            eventBus: eventBus,
            keystore: keystore,
            scheduler: scheduler,
            safroleTicketPool: safroleTicketPool
        )

        dataAvailability = await DataAvailability(
            config: blockchain.config,
            eventBus: eventBus,
            scheduler: scheduler,
            dataProvider: dataProvider,
            dataStore: dataStore
        )
    }

    public func onSyncCompleted() async {
        await blockAuthor.onSyncCompleted()
    }

    public func on(genesis: StateRef) async {
        await safrole.on(genesis: genesis)
        await blockAuthor.on(genesis: genesis)
    }
}
