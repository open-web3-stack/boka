import Blockchain
import RPC
import Utils

public final class NodeDataSource: DataSource {
    public let blockchain: Blockchain
    public let chainDataProvider: BlockchainDataProvider
    public let networkManager: NetworkManager

    public init(blockchain: Blockchain, chainDataProvider: BlockchainDataProvider, networkManager: NetworkManager) {
        self.blockchain = blockchain
        self.chainDataProvider = chainDataProvider
        self.networkManager = networkManager
    }

    public func importBlock(_ block: BlockRef) async throws {
        try await blockchain.importBlock(block)
    }

    public func getBestBlock() async throws -> BlockRef {
        try await chainDataProvider.getBlock(hash: chainDataProvider.bestHead)
    }

    public func getBlock(hash: Data32) async throws -> BlockRef? {
        try await chainDataProvider.getBlock(hash: hash)
    }

    public func getState(hash: Data32) async throws -> StateRef? {
        try await chainDataProvider.getState(hash: hash)
    }

    public func getPeersCount() async throws -> Int {
        networkManager.getPeersCount()
    }
}
