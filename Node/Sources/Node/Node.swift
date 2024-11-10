import Blockchain
import Networking
import RPC
import TracingUtils
import Utils

private let logger = Logger(label: "node")

public typealias RPCConfig = Server.Config
public typealias NetworkConfig = Network.Config

public class Node {
    public struct Config {
        public var rpc: RPCConfig?
        public var network: NetworkConfig
        public var peers: [NetAddr]
        public var local: Bool

        public init(rpc: RPCConfig?, network: NetworkConfig, peers: [NetAddr] = [], local: Bool = false) {
            self.rpc = rpc
            self.network = network
            self.peers = peers
            self.local = local
        }
    }

    public let config: Config
    public let blockchain: Blockchain
    public let rpcServer: Server?
    public let scheduler: Scheduler
    public let dataProvider: BlockchainDataProvider
    public let keystore: KeyStore
    public let network: NetworkManager

    public required init(
        config: Config,
        genesis: Genesis,
        eventBus: EventBus,
        keystore: KeyStore,
        scheduler: Scheduler = DispatchQueueScheduler(timeProvider: SystemTimeProvider())
    ) async throws {
        self.config = config

        let chainspec = try await genesis.load()
        let genesisBlock = try chainspec.getBlock()
        let genesisStateData = try chainspec.getState()
        let backend = try StateBackend(InMemoryBackend(), config: chainspec.getConfig(), rootHash: Data32())
        try await backend.writeRaw(Array(genesisStateData))
        let genesisState = try await State(backend: backend)
        let genesisStateRef = StateRef(genesisState)
        let protocolConfig = try chainspec.getConfig()

        logger.info("Genesis: \(genesisBlock.hash)")

        dataProvider = try await BlockchainDataProvider(InMemoryDataProvider(genesisState: genesisStateRef, genesisBlock: genesisBlock))
        self.scheduler = scheduler
        let blockchain = try await Blockchain(
            config: protocolConfig,
            dataProvider: dataProvider,
            timeProvider: scheduler.timeProvider,
            eventBus: eventBus
        )
        self.blockchain = blockchain

        self.keystore = keystore

        network = try await NetworkManager(
            config: config.network,
            blockchain: blockchain,
            eventBus: eventBus,
            devPeers: Set(config.peers)
        )

        let nodeDataSource = NodeDataSource(blockchain: blockchain, chainDataProvider: dataProvider, networkManager: network)

        rpcServer = try config.rpc.map {
            try Server(config: $0, source: nodeDataSource)
        }
    }

    public func wait() async throws {
        try await rpcServer?.wait()
    }
}
