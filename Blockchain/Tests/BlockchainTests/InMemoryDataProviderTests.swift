import Testing
import Utils

@testable import Blockchain

struct InMemoryDataProviderTests {
    let config = ProtocolConfigRef.mainnet

    @Test func testInitialization() async throws {
        let genesis = StateRef(State.dummy(config: config))
        let block = BlockRef(Block.dummy(config: config))
        let provider = await InMemoryDataProvider(genesisState: genesis, genesisBlock: block)

        #expect(await (provider.getHeads()) == [block.hash])
        #expect(await (provider.getFinalizedHead()) == block.hash)
    }

    @Test func testAddAndRetrieveBlock() async throws {
        let genesis = StateRef(State.dummy(config: config))
        let block = BlockRef(Block.dummy(config: config))

        let provider = await InMemoryDataProvider(genesisState: genesis, genesisBlock: block)

        await provider.add(block: block)

        #expect(await (provider.hasBlock(hash: block.hash)) == true)
        #expect(try await (provider.getBlock(hash: block.hash)) == block)
        await #expect(throws: BlockchainDataProviderError.noData(hash: Data32())) {
            try await provider.getBlock(hash: Data32())
        }
    }

    @Test func testAddAndRetrieveState() async throws {
        let genesis = StateRef(State.dummy(config: config))
        let block = BlockRef(Block.dummy(config: config))

        let provider = await InMemoryDataProvider(genesisState: genesis, genesisBlock: block)

        let state = StateRef(State.dummy(config: config))
        await provider.add(state: state)

        #expect(await (provider.hasState(hash: state.value.lastBlockHash)) == true)
        #expect(try await (provider.getState(hash: state.value.lastBlockHash)) == state)
    }

    @Test func testUpdateHead() async throws {
        let genesis = StateRef(State.dummy(config: config))
        let block = BlockRef(Block.dummy(config: config))
        let provider = await InMemoryDataProvider(genesisState: genesis, genesisBlock: block)

        let newBlock = BlockRef(Block.dummy(config: config))

        await provider.add(block: newBlock)
        try await provider.updateHead(hash: newBlock.hash, parent: Data32())

        #expect(await provider.isHead(hash: newBlock.hash) == true)
        #expect(await provider.isHead(hash: Data32()) == false)

        let hash = Data32.random()
        await #expect(throws: BlockchainDataProviderError.noData(hash: hash)) {
            try await provider.updateHead(hash: newBlock.hash, parent: hash)
        }
    }

    @Test func testSetFinalizedHead() async throws {
        let genesis = StateRef(State.dummy(config: config))
        let block = BlockRef(Block.dummy(config: config))

        let provider = await InMemoryDataProvider(genesisState: genesis, genesisBlock: block)

        await provider.add(block: block)
        await provider.setFinalizedHead(hash: block.hash)

        #expect(await (provider.getFinalizedHead()) == block.hash)
    }

    @Test func testRemoveHash() async throws {
        let genesis = StateRef(State.dummy(config: config))
        let block = BlockRef(Block.dummy(config: config))

        let provider = await InMemoryDataProvider(genesisState: genesis, genesisBlock: block)

        let state = StateRef(State.dummy(config: ProtocolConfigRef.dev))
        let timeslotIndex = state.value.timeslot
        await provider.add(state: state)

        #expect(await (provider.hasState(hash: state.value.lastBlockHash)) == true)
        #expect(await (provider.getBlockHash(byTimeslot: timeslotIndex).contains(state.value.lastBlockHash)) == true)

        await provider.remove(hash: state.value.lastBlockHash)

        #expect(await (provider.hasState(hash: state.value.lastBlockHash)) == false)
        #expect(await (provider.getBlockHash(byTimeslot: timeslotIndex).contains(state.value.lastBlockHash)) == false)
    }
}
