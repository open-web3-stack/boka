import Utils

// TODO: add tests
public actor InMemoryDataProvider: Sendable {
    public private(set) var heads: [StateRef]
    public private(set) var finalizedHead: StateRef
    public private(set) var blocksByHash: [Data32: BlockRef] = [:]

    private var stateByBlockHash: [Data32: StateRef] = [:]
    private var hashByTimeslot: [TimeslotIndex: [Data32]] = [:]

    public init(genesis: StateRef) async {
        heads = [genesis]
        finalizedHead = genesis

        addState(genesis)
    }

    private func addState(_ state: StateRef) {
        stateByBlockHash[state.value.lastBlock.hash] = state
        hashByTimeslot[state.value.lastBlock.header.timeslotIndex, default: []].append(state.value.lastBlock.hash)
    }
}

extension InMemoryDataProvider: BlockchainDataProvider {
    public func hasHeader(hash: Data32) async throws -> Bool {
        stateByBlockHash[hash] != nil
    }

    public func isHead(hash: Data32) async throws -> Bool {
        heads.contains(where: { $0.value.lastBlock.hash == hash })
    }

    public func getHeader(hash: Data32) async throws -> HeaderRef {
        guard let header = stateByBlockHash[hash]?.value.lastBlock.header.asRef() else {
            throw BlockchainDataProviderError.unknownHash
        }
        return header
    }

    public func getBlock(hash: Data32) async throws -> BlockRef {
        guard let block = stateByBlockHash[hash]?.value.lastBlock else {
            throw BlockchainDataProviderError.unknownHash
        }
        return block
    }

    public func getState(hash: Data32) async throws -> StateRef {
        guard let state = stateByBlockHash[hash] else {
            throw BlockchainDataProviderError.unknownHash
        }
        return state
    }

    public func getFinalizedHead() async throws -> Data32 {
        finalizedHead.value.lastBlock.hash
    }

    public func getHeads() async throws -> [Data32] {
        heads.map(\.value.lastBlock.hash)
    }

    public func getBlockHash(index: TimeslotIndex) async throws -> [Data32] {
        hashByTimeslot[index] ?? []
    }

    public func add(state: StateRef, isHead: Bool) async throws {
        addState(state)
        if isHead {
            try await updateHead(hash: state.value.lastBlock.hash, parent: state.value.lastBlock.header.parentHash)
        }
    }

    public func setFinalizedHead(hash: Data32) async throws {
        guard let state = stateByBlockHash[hash] else {
            throw BlockchainDataProviderError.unknownHash
        }
        finalizedHead = state
    }

    public func _updateHeadNoCheck(hash: Data32, parent: Data32) async throws {
        for i in 0 ..< heads.count where heads[i].value.lastBlock.hash == parent {
            assert(stateByBlockHash[hash] != nil)
            heads[i] = stateByBlockHash[hash]!
            return
        }
    }

    public func remove(hash: Data32) async throws {
        guard let state = stateByBlockHash[hash] else {
            return
        }
        stateByBlockHash.removeValue(forKey: hash)
        hashByTimeslot.removeValue(forKey: state.value.lastBlock.header.timeslotIndex)
    }
}
