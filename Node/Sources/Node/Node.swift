import Blockchain

public class Node {
    private var blockchain: Blockchain
    
    public init() {
        blockchain = Blockchain()
    }
    public func sayHello() {
        print("Hello, World!")
    }
}
