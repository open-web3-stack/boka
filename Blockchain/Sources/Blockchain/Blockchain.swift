import Foundation
import TracingUtils
import Utils

public struct BlockImported: Event {
    public var block: BlockRef
    public var state: StateRef
    public var parentState: StateRef
}

public struct BlockFinalized: Event {
    public var hash: Data32
}

/// Holds the state of the blockchain.
/// Includes the canonical chain as well as pending forks.
/// Assume all blocks and states are valid and have been validated.
public final class Blockchain: Sendable {
    public let config: ProtocolConfigRef

    private let dataProvider: BlockchainDataProvider
    private let timeProvider: TimeProvider
    private let eventBus: EventBus

    public init(config: ProtocolConfigRef, dataProvider: BlockchainDataProvider, timeProvider: TimeProvider, eventBus: EventBus) async {
        self.config = config
        self.dataProvider = dataProvider
        self.timeProvider = timeProvider
        self.eventBus = eventBus
    }

    public func importBlock(_ block: BlockRef) async throws {
        try await withSpan("importBlock") { span in
            span.attributes.blockHash = block.hash.description

            let runtime = Runtime(config: config)
            let parent = try await dataProvider.getState(hash: block.header.parentHash)
            let timeslot = timeProvider.getTime() / UInt32(config.value.slotPeriodSeconds)
            let state = try runtime.apply(block: block, state: parent, context: .init(timeslot: timeslot))
            try await dataProvider.add(state: state)

            await eventBus.publish(BlockImported(block: block, state: state, parentState: parent))
        }
    }

    public func finalize(hash: Data32) async throws {
        // TODO: purge forks
        try await dataProvider.setFinalizedHead(hash: hash)
        await eventBus.publish(BlockFinalized(hash: hash))
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
}

extension BlockImported {
    public func isNewEpoch(config: ProtocolConfigRef) -> Bool {
        let epochLength = UInt32(config.value.epochLength)
        let prevEpoch = parentState.value.timeslot / epochLength
        let newEpoch = state.value.timeslot / epochLength
        return prevEpoch != newEpoch
    }
}
