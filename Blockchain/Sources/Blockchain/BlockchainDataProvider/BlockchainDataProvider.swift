import TracingUtils
import Utils

private let logger = Logger(label: "BlockchainDataProvider")

public struct HeadInfo: Sendable {
    public var hash: Data32
    public var timeslot: TimeslotIndex
    public var number: UInt32
}

public actor BlockchainDataProvider: Sendable {
    public private(set) var bestHead: HeadInfo
    public private(set) var finalizedHead: HeadInfo
    private let dataProvider: BlockchainDataProviderProtocol

    public init(_ dataProvider: BlockchainDataProviderProtocol) async throws {
        let heads = try await dataProvider.getHeads()
        var bestHead = HeadInfo(hash: dataProvider.genesisBlockHash, timeslot: 0, number: 0)
        for head in heads {
            let header = try await dataProvider.getHeader(hash: head)
            if header.value.timeslot > bestHead.timeslot {
                let number = try await dataProvider.getBlockNumber(hash: head)
                bestHead = HeadInfo(hash: head, timeslot: header.value.timeslot, number: number)
            }
        }

        self.bestHead = bestHead

        let finalizedHeadHash = try await dataProvider.getFinalizedHead()

        finalizedHead = try await HeadInfo(
            hash: finalizedHeadHash,
            timeslot: dataProvider.getHeader(hash: finalizedHeadHash).value.timeslot,
            number: dataProvider.getBlockNumber(hash: finalizedHeadHash)
        )

        self.dataProvider = dataProvider
    }

    public func blockImported(block: BlockRef, state: StateRef) async throws {
        try await add(block: block)
        try await add(state: state)
        try await dataProvider.updateHead(hash: block.hash, parent: block.header.parentHash)

        if block.header.timeslot > bestHead.timeslot {
            let number = try await dataProvider.getBlockNumber(hash: block.hash)
            bestHead = HeadInfo(hash: block.hash, timeslot: block.header.timeslot, number: number)
        }

        logger.debug("block imported: \(block.hash)")
    }
}

extension BlockchainDataProvider {
    public func hasBlock(hash: Data32) async throws -> Bool {
        try await dataProvider.hasBlock(hash: hash)
    }

    public func hasState(hash: Data32) async throws -> Bool {
        try await dataProvider.hasState(hash: hash)
    }

    public func isHead(hash: Data32) async throws -> Bool {
        try await dataProvider.isHead(hash: hash)
    }

    public func getBlockNumber(hash: Data32) async throws -> UInt32 {
        try await dataProvider.getBlockNumber(hash: hash)
    }

    public func getHeader(hash: Data32) async throws -> HeaderRef {
        try await dataProvider.getHeader(hash: hash)
    }

    public func getBlock(hash: Data32) async throws -> BlockRef {
        try await dataProvider.getBlock(hash: hash)
    }

    public func getState(hash: Data32) async throws -> StateRef {
        try await dataProvider.getState(hash: hash)
    }

    public func getFinalizedHead() async throws -> Data32 {
        try await dataProvider.getFinalizedHead()
    }

    public func getHeads() async throws -> Set<Data32> {
        try await dataProvider.getHeads()
    }

    public func getBlockHash(byTimeslot timeslot: TimeslotIndex) async throws -> Set<Data32> {
        try await dataProvider.getBlockHash(byTimeslot: timeslot)
    }

    public func getBlockHash(byNumber number: UInt32) async throws -> Set<Data32> {
        try await dataProvider.getBlockHash(byNumber: number)
    }

    // add forks of finalized head is not allowed
    public func add(block: BlockRef) async throws {
        logger.debug("adding block: \(block.hash)")

        // require parent exists (i.e. not purged) and block is not fork of any finalized block
        guard try await hasBlock(hash: block.header.parentHash), block.header.timeslot > finalizedHead.timeslot else {
            throw BlockchainDataProviderError.uncanonical(hash: block.hash)
        }

        try await dataProvider.add(block: block)
    }

    /// only allow to add state if the corresponding block is added
    public func add(state: StateRef) async throws {
        logger.debug("adding state: \(state.value.lastBlockHash)")

        // if block exists, that means it passed the canonicalization check
        guard try await hasBlock(hash: state.value.lastBlockHash) else {
            throw BlockchainDataProviderError.noData(hash: state.value.lastBlockHash)
        }

        try await dataProvider.add(state: state)
    }

    /// Also purge fork of all finalized blocks
    public func setFinalizedHead(hash: Data32) async throws {
        logger.debug("setting finalized head: \(hash)")

        let oldFinalizedHead = finalizedHead
        let number = try await dataProvider.getBlockNumber(hash: hash)

        var hashToCheck = hash
        var hashToCheckNumber = number
        while hashToCheck != oldFinalizedHead.hash {
            let hashes = try await dataProvider.getBlockHash(byNumber: hashToCheckNumber)
            for hash in hashes where hash != hashToCheck {
                logger.trace("purge block: \(hash)")
                try await dataProvider.remove(hash: hash)
            }
            hashToCheck = try await dataProvider.getHeader(hash: hashToCheck).value.parentHash
            hashToCheckNumber -= 1
        }

        let header = try await dataProvider.getHeader(hash: hash)
        finalizedHead = HeadInfo(hash: hash, timeslot: header.value.timeslot, number: number)
        try await dataProvider.setFinalizedHead(hash: hash)
    }

    public func remove(hash: Data32) async throws {
        logger.debug("removing block: \(hash)")

        try await dataProvider.remove(hash: hash)
    }

    public var genesisBlockHash: Data32 {
        dataProvider.genesisBlockHash
    }

    public func getBestState() async throws -> StateRef {
        try await dataProvider.getState(hash: bestHead.hash)
    }
}
