public struct PendingBlock {
    public private(set) var block: BlockRef

    public init(block: BlockRef) {
        self.block = block
    }
}
