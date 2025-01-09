import Blockchain
import Database
import Foundation
import Networking
import RPC
import TracingUtils
import Utils

public typealias RPCConfig = Server.Config
public typealias NetworkConfig = Network.Config

private let logger = Logger(label: "config")

public enum Database {
    case inMemory
    case rocksDB(path: URL)

    public func open(chainspec: ChainSpec) async throws -> BlockchainDataProvider {
        switch self {
        case let .rocksDB(path):
            logger.debug("Using RocksDB backend at \(path.absoluteString)")
            let backend = try await RocksDBBackend(
                path: path,
                config: chainspec.getConfig(),
                genesisBlock: chainspec.getBlock(),
                genesisStateData: chainspec.getState()
            )
            return try await BlockchainDataProvider(backend)
        case .inMemory:
            logger.debug("Using in-memory backend")
            let genesisBlock = try chainspec.getBlock()
            let genesisStateData = try chainspec.getState()
            let backend = try StateBackend(InMemoryBackend(), config: chainspec.getConfig(), rootHash: Data32())
            try await backend.writeRaw(Array(genesisStateData))
            let genesisState = try await State(backend: backend)
            let genesisStateRef = StateRef(genesisState)
            return try await BlockchainDataProvider(InMemoryDataProvider(genesisState: genesisStateRef, genesisBlock: genesisBlock))
        }
    }
}

public enum DataStoreKind {
    case inMemory
    case filesystem(path: URL)

    func create() -> DataStore {
        switch self {
        case let .filesystem(path):
            logger.info("Using filesystem data store at \(path.absoluteString)")
            let dataStore = FilesystemDataStore()
            return DataStore(dataStore, basePath: path)
        case .inMemory:
            logger.info("Using in-memory data store")
            return DataStore(InMemoryDataStore(), basePath: URL(filePath: "/tmp/boka"))
        }
    }
}

public struct Config {
    public var rpc: RPCConfig?
    public var network: NetworkConfig
    public var peers: [NetAddr]
    public var local: Bool
    public var name: String?
    public var database: Database
    public var dataStore: DataStoreKind

    public init(
        rpc: RPCConfig?,
        network: NetworkConfig,
        peers: [NetAddr] = [],
        local: Bool = false,
        name: String? = nil,
        database: Database = .inMemory,
        dataStore: DataStoreKind = .inMemory
    ) {
        self.rpc = rpc
        self.network = network
        self.peers = peers
        self.local = local
        self.name = name
        self.database = database
        self.dataStore = dataStore
    }
}
