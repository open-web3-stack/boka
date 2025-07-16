import TracingUtils
import Utils

private let logger = Logger(label: "BlockchainDataProvider")

public struct HeadInfo: Sendable {
    public var hash: Data32
    public var timeslot: TimeslotIndex
    public var number: UInt32
}

public enum BlockchainDataProviderError: Error, Equatable {
    case noData(hash: Data32)
    case uncanonical(hash: Data32)
}

public actor BlockchainDataProvider {
    public private(set) var bestHead: HeadInfo
    public private(set) var finalizedHead: HeadInfo
    private let dataProvider: BlockchainDataProviderProtocol

    public init(_ dataProvider: BlockchainDataProviderProtocol) async throws {
        let heads = try await dataProvider.getHeads()
        var bestHead = HeadInfo(hash: dataProvider.genesisBlockHash, timeslot: 0, number: 0)
        for head in heads {
            let header = try await dataProvider.getHeader(hash: head).unwrap()
            if header.value.timeslot > bestHead.timeslot {
                let number = try await dataProvider.getBlockNumber(hash: head).unwrap()
                bestHead = HeadInfo(hash: head, timeslot: header.value.timeslot, number: number)
            }
        }

        self.bestHead = bestHead

        let finalizedHeadHash = try await dataProvider.getFinalizedHead().unwrap()

        finalizedHead = try await HeadInfo(
            hash: finalizedHeadHash,
            timeslot: dataProvider.getHeader(hash: finalizedHeadHash).unwrap().value.timeslot,
            number: dataProvider.getBlockNumber(hash: finalizedHeadHash).unwrap()
        )

        self.dataProvider = dataProvider
    }

    public func blockImported(block: BlockRef, state: StateRef) async throws {
        try await add(block: block)
        try await add(state: state)
        try await dataProvider.updateHead(hash: block.hash, parent: block.header.parentHash)

        if block.header.timeslot > bestHead.timeslot {
            let number = try await getBlockNumber(hash: block.hash)
            bestHead = HeadInfo(hash: block.hash, timeslot: block.header.timeslot, number: number)
        }

        logger.debug("Block imported: #\(bestHead.timeslot) \(block.hash)")
    }
}

extension BlockchainDataProvider {
    public func hasGuaranteedWorkReport(hash: Data32) async throws -> Bool {
        try await dataProvider.hasGuaranteedWorkReport(hash: hash)
    }

    public func getGuaranteedWorkReport(hash: Data32) async throws -> GuaranteedWorkReportRef? {
        try await dataProvider.getGuaranteedWorkReport(hash: hash)
    }

    public func add(guaranteedWorkReport: GuaranteedWorkReportRef) async throws {
        try await dataProvider.add(guaranteedWorkReport: guaranteedWorkReport)
    }

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
        try await dataProvider.getBlockNumber(hash: hash).unwrap(orError: BlockchainDataProviderError.noData(hash: hash))
    }

    public func getHeader(hash: Data32) async throws -> HeaderRef {
        try await dataProvider.getHeader(hash: hash).unwrap(orError: BlockchainDataProviderError.noData(hash: hash))
    }

    public func getBlock(hash: Data32) async throws -> BlockRef {
        try await dataProvider.getBlock(hash: hash).unwrap(orError: BlockchainDataProviderError.noData(hash: hash))
    }

    public func getState(hash: Data32) async throws -> StateRef {
        try await dataProvider.getState(hash: hash).unwrap(orError: BlockchainDataProviderError.noData(hash: hash))
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

    public func getFinalizedHead() async throws -> Data32? {
        try await dataProvider.getFinalizedHead()
    }

    public func getKeys(prefix: Data, count: UInt32, startKey: Data31?, blockHash: Data32?) async throws -> [String] {
        try await dataProvider.getKeys(prefix: prefix, count: count, startKey: startKey, blockHash: blockHash)
    }

    public func getStorage(key: Data31, blockHash: Data32?) async throws -> [String] {
        try await dataProvider.getStorage(key: key, blockHash: blockHash)
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
        let number = try await getBlockNumber(hash: hash)

        var hashToCheck = hash
        var hashToCheckNumber = number
        while hashToCheck != oldFinalizedHead.hash {
            let hashes = try await dataProvider.getBlockHash(byNumber: hashToCheckNumber)
            for hash in hashes where hash != hashToCheck {
                logger.trace("purge block: \(hash)")
                try await dataProvider.remove(hash: hash)
            }
            hashToCheck = try await getHeader(hash: hashToCheck).value.parentHash
            hashToCheckNumber -= 1
        }

        let header = try await getHeader(hash: hash)
        finalizedHead = HeadInfo(hash: hash, timeslot: header.value.timeslot, number: number)
        try await dataProvider.setFinalizedHead(hash: hash)
    }

    public func remove(hash: Data32) async throws {
        logger.debug("removing block: \(hash)")
        try await dataProvider.remove(hash: hash)
    }

    public func remove(workReportHash: Data32) async throws {
        logger.debug("removing workReportHash: \(workReportHash)")
        try await dataProvider.remove(workReportHash: workReportHash)
    }

    public nonisolated var genesisBlockHash: Data32 {
        dataProvider.genesisBlockHash
    }

    public func getBestState() async throws -> StateRef {
        try await dataProvider.getState(hash: bestHead.hash).unwrap(orError: BlockchainDataProviderError.noData(hash: bestHead.hash))
    }
}
