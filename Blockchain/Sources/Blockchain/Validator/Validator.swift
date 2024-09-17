import Utils

public class Validator {
    private let blockchain: Blockchain
    private var keystore: KeyStore

    public init(blockchain: Blockchain, keystore: KeyStore) {
        self.blockchain = blockchain
        self.keystore = keystore
    }
}
