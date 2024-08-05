import Blockchain

public class Node {
    public private(set) var blockchain: Blockchain

    public init(genesis: Genesis, config: ProtocolConfigRef) async throws {
        let genesisState = try genesis.toState(config: config)
        let dataProvider = await InMemoryDataProvider(genesis: genesisState)
        blockchain = await Blockchain(config: config, dataProvider: dataProvider)
    }

    public func sayHello() {
        print("Hello, World!")
    }
}
