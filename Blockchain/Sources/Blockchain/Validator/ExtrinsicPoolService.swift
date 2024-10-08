import TracingUtils
import Utils

private typealias TicketItem = ExtrinsicTickets.TicketItem

private actor ServiceStorage {
    let logger: Logger

    // sorted array ordered by output
    var pendingTickets: SortedUniqueArray<TicketItemAndOutput> = .init()
    var epoch: EpochIndex = 0
    var verifier: Bandersnatch.Verifier!
    var entropy: Data32 = .init()
    let ringContext: Bandersnatch.RingContext

    init(logger: Logger, ringContext: Bandersnatch.RingContext) {
        self.logger = logger
        self.ringContext = ringContext
    }

    func add(tickets: [TicketItem], config: ProtocolConfigRef) {
        for ticket in tickets {
            if (try? ticket.validate(config: config)) == nil {
                logger.info("Received invalid ticket: \(ticket)")
                continue
            }
            let inputData = SigningContext.safroleTicketInputData(entropy: entropy, attempt: ticket.attempt)
            let output = try? verifier.ringVRFVerify(vrfInputData: inputData, signature: ticket.signature)
            guard let output else {
                logger.info("Received invalid ticket: \(ticket)")
                continue
            }
            pendingTickets.insert(.init(ticket: ticket, output: output))
        }
    }

    func add(tickets: [TicketItemAndOutput]) {
        pendingTickets.append(contentsOf: tickets)
    }

    func update(state: StateRef, config: ProtocolConfigRef) throws {
        let epoch = state.value.timeslot.timeslotToEpochIndex(config: config)
        if verifier == nil || self.epoch != epoch {
            let commitment = try Bandersnatch.RingCommitment(data: state.value.safroleState.ticketsVerifier)
            let verifier = Bandersnatch.Verifier(ctx: ringContext, commitment: commitment)

            self.epoch = epoch
            self.verifier = verifier
            entropy = state.value.entropyPool.t3
            pendingTickets.removeAll()
        }
    }

    func removeTickets(tickets: [TicketItem]) {
        pendingTickets.remove { ticket in
            tickets.contains { $0 == ticket.ticket }
        }
    }

    func getPendingTickets(epoch: EpochIndex) -> SortedUniqueArray<TicketItemAndOutput> {
        if epoch != self.epoch {
            .init()
        } else {
            pendingTickets
        }
    }
}

public final class ExtrinsicPoolService: ServiceBase, @unchecked Sendable {
    private var storage: ServiceStorage
    private let dataProvider: BlockchainDataProvider

    public init(
        config: ProtocolConfigRef,
        dataProvider: BlockchainDataProvider,
        eventBus: EventBus
    ) async {
        self.dataProvider = dataProvider

        let logger = Logger(label: "ExtrinsicPoolService")

        let ringContext = try! Bandersnatch.RingContext(size: UInt(config.value.totalNumberOfValidators))
        storage = ServiceStorage(logger: logger, ringContext: ringContext)

        super.init(logger: logger, config: config, eventBus: eventBus)

        await subscribe(RuntimeEvents.SafroleTicketsGenerated.self, id: "ExtrinsicPool.SafroleTicketsGenerated") { [weak self] event in
            try await self?.on(safroleTicketsGenerated: event)
        }

        await subscribe(RuntimeEvents.BlockFinalized.self, id: "ExtrinsicPool.BlockFinalized") { [weak self] event in
            try await self?.on(blockFinalized: event)
        }

        await subscribe(RuntimeEvents.SafroleTicketsReceived.self, id: "ExtrinsicPool.SafroleTicketsReceived") { [weak self] event in
            try await self?.on(safroleTicketsReceived: event)
        }
    }

    private func on(safroleTicketsGenerated tickets: RuntimeEvents.SafroleTicketsGenerated) async throws {
        // Safrole VRF commitments only changes every epoch
        // and we should never receive tickets at very beginning and very end of an epoch
        // so it is safe to use best head state without worrying about forks or edge cases
        let state = try await dataProvider.getState(hash: dataProvider.bestHead)
        try await storage.update(state: state, config: config)
        await storage.add(tickets: tickets.items)
    }

    private func on(safroleTicketsReceived tickets: RuntimeEvents.SafroleTicketsReceived) async throws {
        let state = try await dataProvider.getState(hash: dataProvider.bestHead)

        try await storage.update(state: state, config: config)
        await storage.add(tickets: tickets.items, config: config)
    }

    private func on(blockFinalized event: RuntimeEvents.BlockFinalized) async throws {
        let block = try await dataProvider.getBlock(hash: event.hash)

        await storage.removeTickets(tickets: block.extrinsic.tickets.tickets.array)
    }

    public func getPendingTickets(epoch: EpochIndex) async -> SortedUniqueArray<TicketItemAndOutput> {
        await storage.getPendingTickets(epoch: epoch)
    }
}
