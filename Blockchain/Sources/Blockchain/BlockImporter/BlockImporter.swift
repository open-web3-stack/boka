import AsyncChannels

public struct BlockImporter {
  private var pendingBlocks = Channel<PendingBlock>(capacity: 500)

  public init() {
  }

  public func importBlock(_ block: PendingBlock) {
    pendingBlocks.send(block)
  }
}
