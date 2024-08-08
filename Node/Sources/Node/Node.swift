import Blockchain
import RPC
import TracingUtils

let logger = Logger(label: "node")

public typealias RPCConfig = RPCServer.Config

public class Node {
    public class Config {
        public let rpc: RPCServer.Config
        public let protcol: ProtocolConfigRef

        public init(rpc: RPCServer.Config, protocol: ProtocolConfigRef) {
            self.rpc = rpc
            protcol = `protocol`
        }
    }

    public private(set) var blockchain: Blockchain
    public private(set) var rpcServer: RPCServer

    public init(genesis: Genesis, config: Config) async throws {
        logger.debug("Initializing node")

        let genesisState = try genesis.toState(config: config.protcol)
        let dataProvider = await InMemoryDataProvider(genesis: genesisState)
        blockchain = await Blockchain(config: config.protcol, dataProvider: dataProvider)

        rpcServer = try RPCServer(config: config.rpc, source: blockchain)
    }

    public func sayHello() {
        logger.info("Hello, World!")
    }

    public func wait() async throws {
        try await rpcServer.wait()
    }
}
