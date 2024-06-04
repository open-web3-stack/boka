public struct PendingBlock {
    public private(set) var block: Block

    public init(block: Block) {
        self.block = block
    }
}
