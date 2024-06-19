import Blockchain

public class Node {
    public private(set) var blockchain: Blockchain

    public init(genesis: Genesis) throws {
        let genesisState = try genesis.toState()
        blockchain = Blockchain(heads: [genesisState], finalizedHead: genesisState)
    }

    public func sayHello() {
        print("Hello, World!")
    }
}
