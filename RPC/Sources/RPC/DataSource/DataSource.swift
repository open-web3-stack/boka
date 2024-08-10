import Blockchain
import Utils

public protocol DataSource: Sendable {
    func getBestBlock() async throws -> BlockRef
    func getBlock(hash: Data32) async throws -> BlockRef?

    func importBlock(_: BlockRef) async throws
}
