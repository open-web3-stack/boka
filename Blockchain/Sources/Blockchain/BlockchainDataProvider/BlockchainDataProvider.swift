import TracingUtils
import Utils

private let logger = Logger(label: "BlockchainDataProvider")

private struct BlockchainStorage: Sendable {
    var bestHead: Data32
    var bestHeadTimeslot: TimeslotIndex
    var finalizedHead: Data32
}

public final class BlockchainDataProvider: Sendable {
    private let storage: ThreadSafeContainer<BlockchainStorage>
    private let dataProvider: BlockchainDataProviderProtocol

    public init(_ dataProvider: BlockchainDataProviderProtocol) async throws {
        let heads = try await dataProvider.getHeads()
        var bestHead: (HeaderRef, Data32)?
        for head in heads {
            guard let header = try? await dataProvider.getHeader(hash: head) else {
                continue
            }
            if bestHead == nil || header.value.timeslot > bestHead!.0.value.timeslot {
                bestHead = (header, head)
            }
        }
        let finalizedHead = try await dataProvider.getFinalizedHead()

        storage = ThreadSafeContainer(.init(
            bestHead: bestHead?.1 ?? Data32(),
            bestHeadTimeslot: bestHead?.0.value.timeslot ?? 0,
            finalizedHead: finalizedHead
        ))

        self.dataProvider = dataProvider
    }

    public var bestHead: Data32 {
        storage.value.bestHead
    }

    public var finalizedHead: Data32 {
        storage.value.finalizedHead
    }

    public func blockImported(block: BlockRef, state: StateRef) async throws {
        try await add(block: block)
        try await add(state: state)
        try await updateHead(hash: block.hash, parent: block.header.parentHash)

        if block.header.timeslot > storage.value.bestHeadTimeslot {
            storage.write { storage in
                storage.bestHead = block.hash
                storage.bestHeadTimeslot = block.header.timeslot
            }
        }

        logger.debug("block imported: \(block.hash)")
    }
}

// expose BlockchainDataProviderProtocol
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

    public func add(block: BlockRef) async throws {
        logger.debug("adding block: \(block.hash)")

        try await dataProvider.add(block: block)
    }

    public func add(state: StateRef) async throws {
        logger.debug("adding state: \(state.value.lastBlockHash)")

        try await dataProvider.add(state: state)
    }

    public func setFinalizedHead(hash: Data32) async throws {
        logger.debug("setting finalized head: \(hash)")

        try await dataProvider.setFinalizedHead(hash: hash)
        storage.write { storage in
            storage.finalizedHead = hash
        }
    }

    public func updateHead(hash: Data32, parent: Data32) async throws {
        logger.debug("updating head: \(hash) with parent: \(parent)")

        try await dataProvider.updateHead(hash: hash, parent: parent)
    }

    public func remove(hash: Data32) async throws {
        logger.debug("removing block: \(hash)")

        try await dataProvider.remove(hash: hash)
    }
}
