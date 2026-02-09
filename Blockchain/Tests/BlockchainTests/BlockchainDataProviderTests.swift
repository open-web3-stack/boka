@testable import Blockchain
import Testing
import TracingUtils
import Utils

struct BlockchainDataProviderTests {
    let config = ProtocolConfigRef.mainnet
    let genesisBlock: BlockRef
    let genesisState: StateRef
    let provider: BlockchainDataProvider

    init() async throws {
        // setupTestLogger()

        (genesisState, genesisBlock) = try State.devGenesis(config: config)
        provider = try await BlockchainDataProvider(InMemoryDataProvider(genesisState: genesisState, genesisBlock: genesisBlock))
    }

    // MARK: - Initialization Tests

    @Test func initialization() async throws {
        #expect(await provider.bestHead.hash == genesisBlock.hash)
        #expect(await provider.finalizedHead.hash == genesisBlock.hash)
        #expect(try await provider.getHeads() == [genesisBlock.hash])
    }

    // MARK: - Block Tests

    @Test func blockOperations() async throws {
        // Test block addition
        let block = BlockRef.dummy(config: config, parent: genesisBlock)
        try await provider.add(block: block)

        // Verify block exists
        #expect(try await provider.hasBlock(hash: block.hash))
        #expect(try await provider.getBlock(hash: block.hash) == block)

        // Verify header can be retrieved
        let header = try await provider.getHeader(hash: block.hash)
        #expect(header.value == block.header)

        // Test getting block by timeslot
        let blocks = try await provider.getBlockHash(byTimeslot: block.header.timeslot)
        #expect(blocks.contains(block.hash))
    }

    @Test func blockOperationsErrors() async throws {
        let nonExistentHash = Data32.random()

        // Test getting non-existent block
        await #expect(throws: BlockchainDataProviderError.noData(hash: nonExistentHash)) {
            _ = try await provider.getBlock(hash: nonExistentHash)
        }

        // Test getting non-existent header
        await #expect(throws: BlockchainDataProviderError.noData(hash: nonExistentHash)) {
            _ = try await provider.getHeader(hash: nonExistentHash)
        }

        // Test adding block without parent
        let invalidBlock = BlockRef.dummy(config: config).mutate {
            $0.header.unsigned.parentHash = nonExistentHash
        }
        await #expect(throws: BlockchainDataProviderError.uncanonical(hash: invalidBlock.hash)) {
            try await provider.add(block: invalidBlock)
        }
    }

    // MARK: - State Tests

    @Test func stateOperations() async throws {
        // Test state addition
        let block = BlockRef.dummy(config: config, parent: genesisBlock)
        let state = StateRef.dummy(config: config, block: block)

        try await provider.blockImported(block: block, state: state)

        // Verify state exists
        #expect(try await provider.hasState(hash: block.hash))
        #expect(try await provider.getState(hash: block.hash).value.stateRoot == state.value.stateRoot)

        // Test getting best state
        let bestState = try await provider.getBestState()
        #expect(await bestState.value.stateRoot == state.value.stateRoot)
    }

    @Test func stateOperationsErrors() async throws {
        let nonExistentHash = Data32.random()

        // Test getting non-existent state
        await #expect(throws: BlockchainDataProviderError.noData(hash: nonExistentHash)) {
            _ = try await provider.getState(hash: nonExistentHash)
        }

        let block = BlockRef.dummy(config: config, parent: genesisBlock)

        // Test adding state without corresponding block
        let state = StateRef.dummy(config: config, block: block)
        await #expect(throws: BlockchainDataProviderError.noData(hash: block.hash)) {
            try await provider.add(state: state)
        }
    }

    // MARK: - Head Management Tests

    @Test func headManagement() async throws {
        // Create a chain of blocks
        let block1 = BlockRef.dummy(config: config, parent: genesisBlock)
        let block2 = BlockRef.dummy(config: config, parent: block1)
        let state1 = StateRef.dummy(config: config, block: block1)
        let state2 = StateRef.dummy(config: config, block: block2)

        // Add blocks and states
        try await provider.blockImported(block: block1, state: state1)
        try await provider.blockImported(block: block2, state: state2)

        // Verify head updates
        #expect(await provider.bestHead.hash == block2.hash)
        #expect(try await provider.isHead(hash: block2.hash))

        // Test finalization
        try await provider.setFinalizedHead(hash: block1.hash)
        #expect(await provider.finalizedHead.hash == block1.hash)

        // Verify fork removal
        let fork = BlockRef.dummy(config: config, parent: block1).mutate {
            $0.header.unsigned.extrinsicsHash = Data32.random() // so it is different
        }
        try await provider.add(block: fork)
        try await provider.setFinalizedHead(hash: block2.hash)
        #expect(try await provider.hasBlock(hash: fork.hash) == false)
    }

    @Test func headManagementErrors() async throws {
        let nonExistentHash = Data32.random()

        // Test setting non-existent block as finalized head
        await #expect(throws: BlockchainDataProviderError.noData(hash: nonExistentHash)) {
            try await provider.setFinalizedHead(hash: nonExistentHash)
        }
    }

    // MARK: - Block Number Tests

    @Test func blockNumberOperations() async throws {
        let block1 = BlockRef.dummy(config: config, parent: genesisBlock)
        let block2 = BlockRef.dummy(config: config, parent: block1)

        try await provider.add(block: block1)
        try await provider.add(block: block2)

        // Verify block numbers
        #expect(try await provider.getBlockNumber(hash: genesisBlock.hash) == 0)
        #expect(try await provider.getBlockNumber(hash: block1.hash) == 1)
        #expect(try await provider.getBlockNumber(hash: block2.hash) == 2)

        // Test getting blocks by number
        let blocksAtNumber1 = try await provider.getBlockHash(byNumber: 1)
        #expect(blocksAtNumber1.contains(block1.hash))
    }

    @Test func blockNumberErrors() async throws {
        let nonExistentHash = Data32.random()

        // Test getting number of non-existent block
        await #expect(throws: BlockchainDataProviderError.noData(hash: nonExistentHash)) {
            _ = try await provider.getBlockNumber(hash: nonExistentHash)
        }
    }

    // MARK: - Removal Tests

    @Test func removalOperations() async throws {
        let block = BlockRef.dummy(config: config, parent: genesisBlock)
        let state = StateRef.dummy(config: config, block: block)

        try await provider.add(block: block)
        try await provider.add(state: state)

        // Test removal
        try await provider.remove(hash: block.hash)

        // Verify block and state are removed
        #expect(try await provider.hasBlock(hash: block.hash) == false)
        #expect(try await provider.hasState(hash: block.hash) == false)
    }

    @Test func guaranteedWorkReportOperations() async throws {
        // Create a dummy work report and guaranteed work report
        let workReport = WorkReport.dummy(config: config)
        let guaranteedReport = GuaranteedWorkReport(
            workReport: workReport,
            slot: 1,
            signatures: [],
        )
        let reportRef = guaranteedReport.asRef()

        // Test adding and retrieving
        try await provider.add(guaranteedWorkReport: reportRef)

        // Verify existence
        #expect(try await provider.hasGuaranteedWorkReport(hash: workReport.hash()))

        // Verify retrieval
        let retrieved = try await provider.getGuaranteedWorkReport(hash: workReport.hash())
        #expect(retrieved?.hash == reportRef.hash)
    }

    @Test func guaranteedWorkReportOperationsErrors() async throws {
        let nonExistentHash = Data32.random()
        // Test checking non-existent report
        #expect(try await provider.hasGuaranteedWorkReport(hash: nonExistentHash) == false)
        // Test getting non-existent report
        #expect(try await provider.getGuaranteedWorkReport(hash: nonExistentHash) == nil)
    }
}
