import Blockchain
import Database
import Foundation
import Testing
import Utils

final class RocksDBBackendTests {
    let path = {
        let tmpDir = FileManager.default.temporaryDirectory
        return tmpDir.appendingPathComponent("\(UUID().uuidString)")
    }()

    let config: ProtocolConfigRef = .dev
    let genesisBlock: BlockRef
    var backend: RocksDBBackend!

    init() async throws {
        genesisBlock = BlockRef.dummy(config: config)

        // Initialize backend with genesis block
        backend = try await RocksDBBackend(
            path: path,
            config: config,
            genesisBlock: genesisBlock,
            genesisStateData: [:],
        )
    }

    deinit {
        backend = nil
        try? FileManager.default.removeItem(at: path)
    }

    @Test
    func genesisBlockInitialization() async throws {
        // Verify genesis block was properly stored
        let exists = try await backend.hasBlock(hash: genesisBlock.hash)
        #expect(exists == true)

        // Verify it's both a head and finalized head
        let isHead = try await backend.isHead(hash: genesisBlock.hash)
        #expect(isHead == true)

        let finalizedHead = try await backend.getFinalizedHead()
        #expect(finalizedHead == genesisBlock.hash)

        // Verify block number
        let blockNumber = try await backend.getBlockNumber(hash: genesisBlock.hash)
        #expect(blockNumber == 0)
    }

    @Test
    func blockOperations() async throws {
        // Create and add a new block
        let block1 = BlockRef.dummy(config: config, parent: genesisBlock)

        try await backend.add(block: block1)
        try await backend.updateHead(hash: block1.hash, parent: genesisBlock.hash)

        // Verify block was stored
        let storedBlock = try await backend.getBlock(hash: block1.hash)
        #expect(storedBlock == block1)

        // Verify block indexes
        let blocksByTimeslot = try await backend.getBlockHash(byTimeslot: 1)
        #expect(blocksByTimeslot.contains(block1.hash))

        let blocksByNumber = try await backend.getBlockHash(byNumber: 1)
        #expect(blocksByNumber.contains(block1.hash))

        // Test block removal
        try await backend.remove(hash: block1.hash)
        let exists = try await backend.hasBlock(hash: block1.hash)
        #expect(exists == false)
    }

    @Test
    func chainReorganization() async throws {
        // Create two competing chains
        let block1 = BlockRef.dummy(config: config, parent: genesisBlock)

        let block2 = BlockRef.dummy(config: config, parent: genesisBlock).mutate { block in
            block.header.unsigned.timeslot = 123
        }

        // Add both blocks and update heads
        try await backend.add(block: block1)
        try await backend.add(block: block2)
        try await backend.updateHead(hash: block1.hash, parent: genesisBlock.hash)
        try await backend.updateHead(hash: block2.hash, parent: genesisBlock.hash)

        // Verify both are heads
        let heads = try await backend.getHeads()
        #expect(heads.contains(block1.hash))
        #expect(heads.contains(block2.hash))

        // Test finalization of one chain
        try await backend.setFinalizedHead(hash: block1.hash)
        let finalizedHead = try await backend.getFinalizedHead()
        #expect(finalizedHead == block1.hash)
    }
}
