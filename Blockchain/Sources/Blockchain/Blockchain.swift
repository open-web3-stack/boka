import Foundation
import TracingUtils
import Utils

/// Holds the state of the blockchain.
/// Includes the canonical chain as well as pending forks.
/// Assume all blocks and states are valid and have been validated.
public final class Blockchain: Sendable {
    public let config: ProtocolConfigRef

    private let dataProvider: BlockchainDataProvider
    private let timeProvider: TimeProvider

    public init(config: ProtocolConfigRef, dataProvider: BlockchainDataProvider, timeProvider: TimeProvider) async {
        self.config = config
        self.dataProvider = dataProvider
        self.timeProvider = timeProvider
    }

    public func importBlock(_ block: BlockRef) async throws {
        try await withSpan("importBlock") { span in
            span.attributes["hash"] = block.hash.description

            let runtime = Runtime(config: config)
            let parent = try await dataProvider.getState(hash: block.header.parentHash)
            let timeslot = timeProvider.getTime() / UInt32(config.value.slotPeriodSeconds)
            let state = try runtime.apply(block: block, state: parent, context: .init(timeslot: timeslot))
            try await dataProvider.add(state: state)
        }
    }

    public func finalize(hash: Data32) async throws {
        // TODO: purge forks
        try await dataProvider.setFinalizedHead(hash: hash)
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
