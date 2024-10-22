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
        public var rpc: Server.Config?
        public var network: Network.Config

        public init(rpc: Server.Config?, network: Network.Config) {
            self.rpc = rpc
            self.network = network
        }
    }

    public let blockchain: Blockchain
    public let rpcServer: Server?
    public let timeProvider: TimeProvider
    public let dataProvider: BlockchainDataProvider
    public let keystore: KeyStore
    public let network: NetworkManager

    public init(
        config: Config,
        genesis: Genesis,
        eventBus: EventBus,
        keystore: KeyStore
    ) async throws {
        logger.debug("Initializing node")

        let (genesisState, genesisBlock, protocolConfig) = try await genesis.load()
        dataProvider = try await BlockchainDataProvider(InMemoryDataProvider(genesisState: genesisState, genesisBlock: genesisBlock))
        timeProvider = SystemTimeProvider()
        let blockchain = try await Blockchain(
            config: protocolConfig,
            dataProvider: dataProvider,
            timeProvider: timeProvider,
            eventBus: eventBus
        )
        self.blockchain = blockchain

        self.keystore = keystore

        network = try NetworkManager(
            config: config.network,
            blockchain: blockchain
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
