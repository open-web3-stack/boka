import Blockchain
import RPC
import TracingUtils
import Utils

let logger = Logger(label: "node")

public typealias RPCConfig = Server.Config

public class Node {
    public class Config {
        public let rpc: Server.Config
        public let protcol: ProtocolConfigRef

        public init(rpc: Server.Config, protocol: ProtocolConfigRef) {
            self.rpc = rpc
            protcol = `protocol`
        }
    }

    public private(set) var blockchain: Blockchain
    public private(set) var rpcServer: Server

    public init(genesis: Genesis, config: Config, eventBus: EventBus) async throws {
        logger.debug("Initializing node")

        let genesisState = try genesis.toState(config: config.protcol)
        let dataProvider = await InMemoryDataProvider(genesis: genesisState)
        let timeProvider = SystemTimeProvider()
        blockchain = await Blockchain(
            config: config.protcol,
            dataProvider: dataProvider,
            timeProvider: timeProvider,
            eventBus: eventBus
        )

        rpcServer = try Server(config: config.rpc, source: blockchain)
    }

    public func sayHello() {
        logger.info("Hello, World!")
    }

    public func wait() async throws {
        try await rpcServer.wait()
    }
}
