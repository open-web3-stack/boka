import Blockchain

public class Node {
    public private(set) var blockchain: Blockchain

    public init(genesis: StateRef) {
        blockchain = Blockchain(heads: [genesis], finalizedHead: genesis)
    }

    public func sayHello() {
        print("Hello, World!")
    }
}
