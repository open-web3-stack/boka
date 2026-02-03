import Foundation
import TracingUtils
import Utils

/// Main blockchain coordinator for block import and management
///
/// Thread-safety: @unchecked Sendable is safe here because:
/// - Inherits safety from ServiceBase (immutable properties + actors)
/// - All properties are immutable (let)
/// - No mutable shared state beyond base class
public final class Blockchain: ServiceBase, @unchecked Sendable {
    public let dataProvider: BlockchainDataProvider
    public let timeProvider: TimeProvider

    public init(
        config: ProtocolConfigRef,
        dataProvider: BlockchainDataProvider,
        timeProvider: TimeProvider,
        eventBus: EventBus,
    ) async throws {
        self.dataProvider = dataProvider
        self.timeProvider = timeProvider

        super.init(id: "Blockchain", config: config, eventBus: eventBus)

        await subscribe(RuntimeEvents.BlockAuthored.self, id: "Blockchain.BlockAuthored") { [weak self] event in
            try await self?.on(blockAuthored: event)
        }
    }

    private func on(blockAuthored event: RuntimeEvents.BlockAuthored) async throws {
        try await importBlock(event.block)
    }

    public func importBlock(_ block: BlockRef) async throws {
        logger.debug("importing block: #\(block.header.timeslot) \(block.hash)")

        if try await dataProvider.hasBlock(hash: block.hash) {
            logger.debug("block already imported", metadata: ["hash": "\(block.hash)"])
            return
        }
        // TODO: if current block is light
        // check if dataProvider.hasGuaranteedWorkReport
        // send workReportDistribution waiting for response
        // save to full block
        try await withSpan("importBlock") { span in
            span.attributes.blockHash = block.hash.description

            let runtime = try Runtime(config: config, ancestry: .init(config: config))
            let parent = try await dataProvider.getState(hash: block.header.parentHash)
            let stateRoot = await parent.value.stateRoot
            let timeslot = timeProvider.getTime().timeToTimeslot(config: config)
            // TODO: figure out what is the best way to deal with block received a bit too early
            let context = Runtime.ApplyContext(timeslot: timeslot + 1, stateRoot: stateRoot)
            let state = try await runtime.apply(block: block, state: parent, context: context)

            try await dataProvider.blockImported(block: block, state: state)

            publish(RuntimeEvents.BlockImported(block: block, state: state, parentState: parent))
        }
    }

    public func finalize(hash: Data32) async throws {
        logger.debug("finalizing block: \(hash)")

        // TODO: purge forks
        try await dataProvider.setFinalizedHead(hash: hash)

        publish(RuntimeEvents.BlockFinalized(hash: hash))
    }

    public func publish(event: some Event) {
        publish(event)
    }

    public func waitFor<T: Event>(
        _ eventType: T.Type,
        check: @escaping @Sendable (T) -> Bool = { _ in true },
        timeout: TimeInterval = 10,
    ) async throws -> T {
        try await waitFor(eventType: eventType, check: check, timeout: timeout)
    }
}
