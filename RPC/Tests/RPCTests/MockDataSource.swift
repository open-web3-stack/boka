import Blockchain
import RPC
import Utils

actor MockDataSource: DataSource, @unchecked Sendable {
    var bestBlock: BlockRef
    var blocks: [Data32: BlockRef] = [:]
    var importedBlocks: [BlockRef] = []

    init(bestBlock: BlockRef) {
        self.bestBlock = bestBlock
    }

    func getBestBlock() async throws -> BlockRef {
        bestBlock
    }

    func getBlock(hash: Data32) async throws -> BlockRef? {
        blocks[hash]
    }

    func importBlock(_: BlockRef) async throws {
        importedBlocks.append(bestBlock)
    }
}
