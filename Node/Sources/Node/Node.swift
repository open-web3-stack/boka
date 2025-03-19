import Blockchain
import Database
import Foundation
import Networking
import RPC
import TracingUtils
import Utils

private let logger = Logger(label: "node")

public class Node {
    public let config: Config
    public let blockchain: Blockchain
    public let rpcServer: Server?
    public let scheduler: Scheduler
    public let dataProvider: BlockchainDataProvider
    public let dataStore: DataStore
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
        let protocolConfig = try chainspec.getConfig()

        (dataProvider, dataStore) = try await config.database.open(chainspec: chainspec)

        logger.info("Genesis: \(dataProvider.genesisBlockHash)")

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
            buildNetwork: { handler in
                try Network(
                    config: config.network,
                    protocolConfig: blockchain.config,
                    genesisHeader: blockchain.dataProvider.genesisBlockHash,
                    handler: handler
                )
            },
            blockchain: blockchain,
            eventBus: eventBus,
            devPeers: Set(config.peers)
        )

        let nodeDataSource = NodeDataSource(
            blockchain: blockchain,
            chainDataProvider: dataProvider,
            networkManager: network,
            keystore: keystore,
            name: config.name
        )

        rpcServer = try config.rpc.map {
            try Server(config: $0, source: nodeDataSource)
        }
    }

    public func wait() async throws {
        try await rpcServer?.wait()
    }
}
