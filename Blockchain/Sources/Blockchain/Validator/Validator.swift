import Utils

public class Validator {
    private let blockchain: Blockchain
    private var keystore: KeyStore
    private let safrole: SafroleService

    public init(blockchain: Blockchain, keystore: KeyStore, eventBus: EventBus) async {
        self.blockchain = blockchain
        self.keystore = keystore

        safrole = await SafroleService(
            config: blockchain.config,
            eventBus: eventBus,
            keystore: keystore
        )
    }
}
