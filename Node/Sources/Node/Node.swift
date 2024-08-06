import Blockchain
import TracingUtils

let logger = Logger(label: "node")

public class Node {
    public private(set) var blockchain: Blockchain

    public init(genesis: Genesis, config: ProtocolConfigRef) async throws {
        logger.debug("Initializing node")

        let genesisState = try genesis.toState(config: config)
        let dataProvider = await InMemoryDataProvider(genesis: genesisState)
        blockchain = await Blockchain(config: config, dataProvider: dataProvider)
    }

    public func sayHello() {
        logger.info("Hello, World!")
    }
}
