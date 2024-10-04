import Blockchain
import RPC
import TracingUtils
import Utils

let logger = Logger(label: "node")

public typealias RPCConfig = Server.Config

public class Node {
    public class Config {
        public let rpc: Server.Config

        public init(rpc: Server.Config) {
            self.rpc = rpc
        }
    }

    public let blockchain: Blockchain
    public let rpcServer: Server
    public let timeProvider: TimeProvider
    public let dataProvider: BlockchainDataProvider

    public init(
        config: Config,
        genesis: Genesis,
        eventBus: EventBus
    ) async throws {
        logger.debug("Initializing node")

        let (genesisState, protocolConfig) = try await genesis.load()
        dataProvider = try await BlockchainDataProvider(InMemoryDataProvider(genesis: genesisState))
        timeProvider = SystemTimeProvider(slotPeriodSeconds: UInt32(protocolConfig.value.slotPeriodSeconds))
        blockchain = try await Blockchain(
            config: protocolConfig,
            dataProvider: dataProvider,
            timeProvider: timeProvider,
            eventBus: eventBus
        )

        rpcServer = try Server(config: config.rpc, source: blockchain)
    }

    public func wait() async throws {
        try await rpcServer.wait()
    }
}
