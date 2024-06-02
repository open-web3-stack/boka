import Blockchain

public class Node {
    public private(set) var blockchain: Blockchain
    
    public init() {
        blockchain = Blockchain()
    }
    public func sayHello() {
        print("Hello, World!")
    }
}
