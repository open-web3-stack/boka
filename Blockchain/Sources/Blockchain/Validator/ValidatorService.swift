import Foundation
import Utils

public final class ValidatorService: Sendable {
    private let blockchain: Blockchain
    private let keystore: KeyStore
    private let safrole: SafroleService
    private let extrinsicPool: ExtrinsicPoolService
    private let blockAuthor: BlockAuthor

    public init(
        blockchain: Blockchain,
        keystore: KeyStore,
        eventBus: EventBus,
        scheduler: Scheduler,
        dataProvider: BlockchainDataProvider
    ) async {
        self.blockchain = blockchain
        self.keystore = keystore

        safrole = await SafroleService(
            config: blockchain.config,
            eventBus: eventBus,
            keystore: keystore
        )

        extrinsicPool = await ExtrinsicPoolService(
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
            extrinsicPool: extrinsicPool
        )
    }

    public func on(genesis: StateRef) async {
        await safrole.on(genesis: genesis)
        await blockAuthor.on(genesis: genesis)
    }
}
