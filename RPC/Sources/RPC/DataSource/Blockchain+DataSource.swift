import Blockchain
import Utils

extension Blockchain: DataSource {
    public func getBestBlock() async throws -> BlockRef {
        try await dataProvider.getBlock(hash: dataProvider.bestHead)
    }

    public func getBlock(hash: Data32) async throws -> BlockRef? {
        try await dataProvider.getBlock(hash: hash)
    }

    public func getState(hash: Data32) async throws -> StateRef? {
        try await dataProvider.getState(hash: hash)
    }
}
