public final class BlockImporter {
    private var blockchain: Blockchain

    public init(blockchain: Blockchain) {
        self.blockchain = blockchain
    }

    public func importBlock(_ block: PendingBlock) async throws {
        let runtime = Runtime(config: blockchain.config)
        let state = try await runtime.apply(block: block.block, state: blockchain.heads.last!)

        await blockchain.newHead(state)
    }
}
