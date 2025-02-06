import Blockchain
@testable import Node
@testable import RPC
import Testing
import TracingUtils
@testable import Utils
import Vapor

public class DummyNodeDataSource {
    public let blockchain: Blockchain
    public let scheduler: Scheduler
    public let dataProvider: BlockchainDataProvider
    public let network: NetworkManager
    public let nodeDataSource: NodeDataSource
    public required init(
        genesis: Genesis,
        scheduler: Scheduler = DispatchQueueScheduler(timeProvider: SystemTimeProvider())
    ) async throws {
        let keystore = try await DevKeyStore(devKeysCount: 0)
        let keys = try await keystore.addDevKeys(seed: 0)
        let eventBus = EventBus(eventMiddleware: .serial(Middleware(storeMiddleware), .noError), handlerMiddleware: .noError)
        let (genesisState, genesisBlock) = try! State.devGenesis(config: .minimal)

        let config = await Config(
            rpc: nil,
            network: Network.Config(
                role: .builder,
                listenAddress: NetAddr(address: "127.0.0.1:0")!,
                key: keystore.get(Ed25519.self, publicKey: keys.ed25519)!
            ),
            peers: [],
            local: true
        )

        let chainspec = try await genesis.load()
        let protocolConfig = try chainspec.getConfig()

        dataProvider = try! await BlockchainDataProvider(InMemoryDataProvider(genesisState: genesisState, genesisBlock: genesisBlock))

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

        nodeDataSource = NodeDataSource(
            blockchain: blockchain,
            chainDataProvider: dataProvider,
            networkManager: network,
            name: config.name
        )
    }
}
