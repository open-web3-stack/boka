import Utils

public actor InMemoryDataProvider {
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
    public func hasGuaranteedWorkReport(hash _: Data32) async throws -> Bool {
        true
    }

    public func getGuaranteedWorkReport(hash _: Data32) async throws -> GuaranteedWorkReportRef? {
        nil
    }

    public func add(guaranteedWorkReport _: GuaranteedWorkReportRef) async throws {}

    public func getKeys(prefix: Data32, count: UInt32, startKey: Data32?, blockHash: Data32?) async throws -> [String] {
        guard let stateRef = try getState(hash: blockHash ?? genesisBlockHash) else {
            return []
        }

        return try await stateRef.value.backend.getKeys(prefix, startKey, count).map { $0.key.toHexString() }
    }

    public func getStorage(key: Data32, blockHash: Data32?) async throws -> [String] {
        guard let stateRef = try getState(hash: blockHash ?? genesisBlockHash) else {
            return []
        }

        guard let value = try await stateRef.value.backend.readRaw(key) else {
            throw StateBackendError.missingState(key: key)
        }
        return [value.toHexString()]
    }

    public func hasBlock(hash: Data32) -> Bool {
        blockByHash[hash] != nil
    }

    public func hasState(hash: Data32) -> Bool {
        stateByBlockHash[hash] != nil
    }

    public func isHead(hash: Data32) -> Bool {
        heads.contains(hash)
    }

    public func getBlockNumber(hash: Data32) async throws -> UInt32? {
        numberByHash[hash]
    }

    public func getHeader(hash: Data32) throws -> HeaderRef? {
        blockByHash[hash]?.header.asRef()
    }

    public func getBlock(hash: Data32) throws -> BlockRef? {
        blockByHash[hash]
    }

    public func getState(hash: Data32) throws -> StateRef? {
        stateByBlockHash[hash]
    }

    public func getFinalizedHead() -> Data32? {
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
        let blockNumber = if let number = numberByHash[block.header.parentHash] {
            number + 1
        } else {
            UInt32(0)
        }
        numberByHash[block.hash] = blockNumber
        hashByNumber[blockNumber, default: Set()].insert(block.hash)
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
        blockByHash.removeValue(forKey: hash)

        if let timeslot {
            hashByTimeslot[timeslot]?.remove(hash)
        }

        let number = numberByHash.removeValue(forKey: hash)

        if let number {
            hashByNumber[number]?.remove(hash)
        }

        heads.remove(hash)
    }
}
