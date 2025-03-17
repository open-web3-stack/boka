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

public enum KeyStoreType {
    case inMemory
    case file(path: URL)

    public func getStore() throws -> KeyStore {
        switch self {
        case let .file(path):
            try FilesystemKeyStore(storageDirectory: path)
        case .inMemory:
            InMemoryKeyStore()
        }
    }
}

public enum Database {
    case inMemory
    case rocksDB(path: URL)

    public func open(chainspec: ChainSpec) async throws -> (BlockchainDataProvider, DataStore) {
        switch self {
        case let .rocksDB(path):
            logger.debug("Using RocksDB backend at \(path.absoluteString)")
            let backend = try await RocksDBBackend(
                path: path,
                config: chainspec.getConfig(),
                genesisBlock: chainspec.getBlock(),
                genesisStateData: chainspec.getState()
            )
            let dataProvider = try await BlockchainDataProvider(backend)
            // TODO: implement RocksDBDataStoreBackend
            let dataStore = DataStore(InMemoryDataStoreBackend(), InMemoryDataStoreBackend())
            return (dataProvider, dataStore)
        case .inMemory:
            logger.debug("Using in-memory backend")
            let genesisBlock = try chainspec.getBlock()
            let genesisStateData = try chainspec.getState()
            let backend = try StateBackend(InMemoryBackend(), config: chainspec.getConfig(), rootHash: Data32())
            try await backend.writeRaw(Array(genesisStateData))
            let genesisState = try await State(backend: backend)
            let genesisStateRef = StateRef(genesisState)
            let dataProvider = try await BlockchainDataProvider(InMemoryDataProvider(
                genesisState: genesisStateRef,
                genesisBlock: genesisBlock
            ))
            let dataStore = DataStore(InMemoryDataStoreBackend(), InMemoryDataStoreBackend())
            return (dataProvider, dataStore)
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
    public var keystoreType: KeyStoreType

    public init(
        rpc: RPCConfig?,
        network: NetworkConfig,
        peers: [NetAddr] = [],
        local: Bool = false,
        name: String? = nil,
        database: Database = .inMemory,
        keystoreType: KeyStoreType = .inMemory
    ) {
        self.rpc = rpc
        self.network = network
        self.peers = peers
        self.local = local
        self.name = name
        self.database = database
        self.keystoreType = keystoreType
    }
}
