import Blockchain
import Foundation
import RPC
import Utils

public final class NodeDataSource: Sendable {
    public let blockchain: Blockchain
    public let chainDataProvider: BlockchainDataProvider
    public let networkManager: NetworkManager
    public let name: String

    public init(
        blockchain: Blockchain,
        chainDataProvider: BlockchainDataProvider,
        networkManager: NetworkManager,
        name: String?
    ) {
        self.blockchain = blockchain
        self.chainDataProvider = chainDataProvider
        self.networkManager = networkManager
        self.name = name ?? "(no name)" // TODO: generate a random name
    }
}

extension NodeDataSource: SystemDataSource {}

extension NodeDataSource: ChainDataSource {
    public func getBestBlock() async throws -> BlockRef {
        try await chainDataProvider.getBlock(hash: chainDataProvider.bestHead.hash)
    }

    public func getBlock(hash: Data32) async throws -> BlockRef? {
        try await chainDataProvider.getBlock(hash: hash)
    }

    public func getState(blockHash: Data32, key: Data32) async throws -> Data? {
        let state = try await chainDataProvider.getState(hash: blockHash)
        return try await state.value.read(key: key)
    }
}

extension NodeDataSource: TelemetryDataSource {
    public func name() async throws -> String {
        name
    }

    public func getPeersCount() async throws -> Int {
        networkManager.peersCount
    }
}
