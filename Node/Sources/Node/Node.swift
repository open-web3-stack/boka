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

        public init(rpc: RPCConfig?, network: NetworkConfig, peers: [NetAddr] = []) {
            self.rpc = rpc
            self.network = network
            self.peers = peers
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

        network = try await NetworkManager(
            config: config.network,
            blockchain: blockchain,
            eventBus: eventBus,
            devPeers: Set(config.peers)
        )

        rpcServer = try config.rpc.map {
            try Server(config: $0, source: blockchain)
        }
    }

    public func wait() async throws {
        try await rpcServer?.wait()
    }
}
