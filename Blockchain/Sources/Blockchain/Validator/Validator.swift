import Utils

public class Validator {
    private let blockchain: Blockchain
    private var keystore: KeyStore
    private let safrole: SafroleService
    private let extrinsicPool: ExtrinsicPoolService

    public init(blockchain: Blockchain, keystore: KeyStore, eventBus: EventBus) async {
        self.blockchain = blockchain
        self.keystore = keystore

        safrole = await SafroleService(
            config: blockchain.config,
            eventBus: eventBus,
            keystore: keystore
        )

        extrinsicPool = await ExtrinsicPoolService(
            blockchain: blockchain,
            eventBus: eventBus
        )
    }

    public func on(genesis: StateRef) async {
        await safrole.on(genesis: genesis)
    }
}
