public class BlockImporter {
    private var validator: BlockValidator
    private var blockchain: Blockchain

    public init(validator: BlockValidator, blockchain: Blockchain) {
        self.validator = validator
        self.blockchain = blockchain
    }

    public func importBlock(_ block: PendingBlock) async {
        let result = await validator.validate(block: block, chain: blockchain)

        switch result {
        case let .success(state):
            blockchain.newHead(state)

        case .failure(.future):
            // TODO: save this somewhere else and import it later
            break

        case .failure(.invalid):
            break
        }
    }
}
