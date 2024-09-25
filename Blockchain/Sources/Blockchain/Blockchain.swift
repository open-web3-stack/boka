import Foundation
import TracingUtils
import Utils

private struct BlockchainStorage: Sendable {
    var bestHead: Data32?
    var bestHeadTimeslot: TimeslotIndex?
    var finalizedHead: Data32
}

/// Holds the state of the blockchain.
/// Includes the canonical chain as well as pending forks.
/// Assume all blocks and states are valid and have been validated.
public final class Blockchain: Sendable {
    public let config: ProtocolConfigRef

    private let storage: ThreadSafeContainer<BlockchainStorage>
    private let dataProvider: BlockchainDataProvider
    private let timeProvider: TimeProvider
    private let eventBus: EventBus

    public init(
        config: ProtocolConfigRef,
        dataProvider: BlockchainDataProvider,
        timeProvider: TimeProvider,
        eventBus: EventBus
    ) async throws {
        self.config = config
        self.dataProvider = dataProvider
        self.timeProvider = timeProvider
        self.eventBus = eventBus

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
            bestHead: bestHead?.1,
            bestHeadTimeslot: bestHead?.0.value.timeslot,
            finalizedHead: finalizedHead
        ))
    }

    public func importBlock(_ block: BlockRef) async throws {
        try await withSpan("importBlock") { span in
            span.attributes.blockHash = block.hash.description

            let runtime = Runtime(config: config)
            let parent = try await dataProvider.getState(hash: block.header.parentHash)
            let timeslot = timeProvider.getTime() / UInt32(config.value.slotPeriodSeconds)
            let state = try runtime.apply(block: block, state: parent, context: .init(timeslot: timeslot))
            try await dataProvider.add(state: state)

            // update best head
            if state.value.timeslot > storage.value.bestHeadTimeslot ?? 0 {
                storage.mutate { storage in
                    storage.bestHead = block.hash
                    storage.bestHeadTimeslot = state.value.timeslot
                }
            }

            await eventBus.publish(RuntimeEvents.BlockImported(block: block, state: state, parentState: parent))
        }
    }

    public func finalize(hash: Data32) async throws {
        // TODO: purge forks
        try await dataProvider.setFinalizedHead(hash: hash)

        storage.write { storage in
            storage.finalizedHead = hash
        }

        await eventBus.publish(RuntimeEvents.BlockFinalized(hash: hash))
    }

    public func getBestBlock() async throws -> BlockRef {
        guard let hash = try await dataProvider.getHeads().first else {
            try throwUnreachable("no head")
        }
        return try await dataProvider.getBlock(hash: hash)
    }

    public func getBlock(hash: Data32) async throws -> BlockRef? {
        try await dataProvider.getBlock(hash: hash)
    }

    public func getState(hash: Data32) async throws -> StateRef? {
        try await dataProvider.getState(hash: hash)
    }

    public var bestHead: Data32 {
        storage.value.bestHead ?? Data32()
    }

    public var finalizedHead: Data32 {
        storage.value.finalizedHead
    }
}
