import Utils

public actor InMemoryDataProvider: Sendable {
    public private(set) var heads: Set<Data32>
    public private(set) var finalizedHead: Data32

    private var hashByNumber: [UInt32: Set<Data32>] = [:]
    private var numberByHash: [Data32: UInt32] = [:]
    private var blockByHash: [Data32: BlockRef] = [:]
    private var stateByBlockHash: [Data32: StateRef] = [:]
    private var hashByTimeslot: [TimeslotIndex: Set<Data32>] = [:]
    public let genesisBlockHash: Data32

    public init(genesisState: StateRef, genesisBlock: BlockRef) async {
        genesisBlockHash = genesisBlock.hash
        heads = [genesisBlockHash]
        finalizedHead = genesisBlockHash

        add(block: genesisBlock)
        add(state: genesisState)
    }
}

extension InMemoryDataProvider: BlockchainDataProviderProtocol {
    public func hasBlock(hash: Data32) -> Bool {
        blockByHash[hash] != nil
    }

    public func hasState(hash: Data32) -> Bool {
        stateByBlockHash[hash] != nil
    }

    public func isHead(hash: Data32) -> Bool {
        heads.contains(hash)
    }

    public func getBlockNumber(hash: Data32) async throws -> UInt32 {
        guard let number = numberByHash[hash] else {
            throw BlockchainDataProviderError.noData(hash: hash)
        }
        return number
    }

    public func getHeader(hash: Data32) throws -> HeaderRef {
        guard let header = blockByHash[hash]?.header.asRef() else {
            throw BlockchainDataProviderError.noData(hash: hash)
        }
        return header
    }

    public func getBlock(hash: Data32) throws -> BlockRef {
        guard let block = blockByHash[hash] else {
            throw BlockchainDataProviderError.noData(hash: hash)
        }
        return block
    }

    public func getState(hash: Data32) throws -> StateRef {
        guard let state = stateByBlockHash[hash] else {
            throw BlockchainDataProviderError.noData(hash: hash)
        }
        return state
    }

    public func getFinalizedHead() -> Data32 {
        finalizedHead
    }

    public func getHeads() -> Set<Data32> {
        heads
    }

    public func getBlockHash(byTimeslot timeslot: TimeslotIndex) -> Set<Data32> {
        hashByTimeslot[timeslot] ?? Set()
    }

    public func getBlockHash(byNumber number: UInt32) -> Set<Data32> {
        hashByNumber[number] ?? Set()
    }

    public func add(state: StateRef) {
        stateByBlockHash[state.value.lastBlockHash] = state
        hashByTimeslot[state.value.timeslot, default: Set()].insert(state.value.lastBlockHash)
    }

    public func add(block: BlockRef) {
        blockByHash[block.hash] = block
        hashByTimeslot[block.header.timeslot, default: Set()].insert(block.hash)
        if let number = numberByHash[block.header.parentHash] {
            numberByHash[block.hash] = number + 1
        } else {
            numberByHash[block.hash] = 0
        }
    }

    public func setFinalizedHead(hash: Data32) {
        finalizedHead = hash
    }

    public func updateHead(hash: Data32, parent: Data32) throws {
        // parent needs to be either
        // - existing head
        // - known block
        guard heads.remove(parent) != nil || hasBlock(hash: parent) else {
            throw BlockchainDataProviderError.noData(hash: parent)
        }
        heads.insert(hash)
    }

    public func remove(hash: Data32) {
        let timeslot = blockByHash[hash]?.header.timeslot ?? stateByBlockHash[hash]?.value.timeslot
        stateByBlockHash.removeValue(forKey: hash)

        if let timeslot {
            hashByTimeslot[timeslot]?.remove(hash)
        }

        let number = numberByHash.removeValue(forKey: hash)

        if let number {
            hashByNumber[number]?.remove(hash)
        }
    }
}
