import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "Blockchain")

public final class Blockchain: ServiceBase, @unchecked Sendable {
    public let dataProvider: BlockchainDataProvider
    public let timeProvider: TimeProvider

    public init(
        config: ProtocolConfigRef,
        dataProvider: BlockchainDataProvider,
        timeProvider: TimeProvider,
        eventBus: EventBus
    ) async throws {
        self.dataProvider = dataProvider
        self.timeProvider = timeProvider

        super.init(config, eventBus)

        await subscribe(RuntimeEvents.BlockAuthored.self, id: "Blockchain.BlockAuthored") { [weak self] event in
            try await self?.on(blockAuthored: event)
        }
    }

    private func on(blockAuthored event: RuntimeEvents.BlockAuthored) async throws {
        try await importBlock(event.block)
    }

    public func importBlock(_ block: BlockRef) async throws {
        logger.debug("importing block: #\(block.header.timeslot) \(block.hash)")

        try await withSpan("importBlock") { span in
            span.attributes.blockHash = block.hash.description

            let runtime = Runtime(config: config)
            let parent = try await dataProvider.getState(hash: block.header.parentHash)
            let timeslot = timeProvider.getTimeslot()
            let state = try runtime.apply(block: block, state: parent, context: .init(timeslot: timeslot))

            try await dataProvider.blockImported(block: block, state: state)

            publish(RuntimeEvents.BlockImported(block: block, state: state, parentState: parent))

            logger.info("Block imported: #\(block.header.timeslot) \(block.hash)")
        }
    }

    public func finalize(hash: Data32) async throws {
        logger.debug("finalizing block: \(hash)")

        // TODO: purge forks
        try await dataProvider.setFinalizedHead(hash: hash)

        publish(RuntimeEvents.BlockFinalized(hash: hash))
    }
}
