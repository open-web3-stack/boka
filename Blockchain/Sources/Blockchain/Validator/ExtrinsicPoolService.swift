import TracingUtils
import Utils

private typealias TicketItem = ExtrinsicTickets.TicketItem
public struct TicketItemAndOutput: Comparable, Sendable {
    public let ticket: ExtrinsicTickets.TicketItem
    public let output: Data32

    public static func < (lhs: TicketItemAndOutput, rhs: TicketItemAndOutput) -> Bool {
        lhs.output < rhs.output
    }

    public static func == (lhs: TicketItemAndOutput, rhs: TicketItemAndOutput) -> Bool {
        lhs.output == rhs.output && lhs.ticket == rhs.ticket
    }
}

private let logger = Logger(label: "ExtrinsicPoolService")

private actor ServiceStorage {
    // sorted array ordered by output
    var pendingTickets: SortedArray<TicketItemAndOutput> = .init()
    var epoch: EpochIndex = 0
    var verifier: Bandersnatch.Verifier!
    var entropy: Data32 = .init()
    let ringContext: Bandersnatch.RingContext

    init(ringContext: Bandersnatch.RingContext) {
        self.ringContext = ringContext
    }

    private func add(tickets: [TicketItem]) {
        for ticket in tickets {
            let inputData = SigningContext.safroleTicketInputData(entropy: entropy, attempt: ticket.attempt)
            let output = try? verifier.ringVRFVerify(vrfInputData: inputData, signature: ticket.signature.data)
            guard let output else {
                logger.info("Received invalid ticket: \(ticket)")
                continue
            }
            pendingTickets.insert(.init(ticket: ticket, output: output))
        }
    }

    func update(state: StateRef, config: ProtocolConfigRef, tickets: [TicketItem]) throws {
        let epoch = state.value.timeslot.toEpochIndex(config: config)
        if verifier == nil || self.epoch != epoch {
            let commitment = try Bandersnatch.RingCommitment(data: state.value.safroleState.ticketsVerifier)
            let verifier = Bandersnatch.Verifier(ctx: ringContext, commitment: commitment)

            self.epoch = epoch
            self.verifier = verifier
            entropy = state.value.entropyPool.t2
            pendingTickets.removeAll()
        }

        add(tickets: tickets)
    }

    func removeTickets(tickets: [TicketItem]) {
        pendingTickets.remove { ticket in
            !tickets.contains { $0 == ticket.ticket }
        }
    }
}

public final class ExtrinsicPoolService: ServiceBase, @unchecked Sendable {
    private var storage: ServiceStorage
    private let blockchain: Blockchain

    public init(blockchain: Blockchain, eventBus: EventBus) async {
        self.blockchain = blockchain

        let ringContext = try! Bandersnatch.RingContext(size: UInt(blockchain.config.value.totalNumberOfValidators))
        storage = ServiceStorage(ringContext: ringContext)

        super.init(blockchain.config, eventBus)

        await subscribe(RuntimeEvents.NewSafroleTickets.self) { [weak self] event in
            try await self?.on(newSafroleTickets: event)
        }

        await subscribe(RuntimeEvents.BlockFinalized.self) { [weak self] event in
            try await self?.on(blockFinalized: event)
        }
    }

    private func on(newSafroleTickets tickets: RuntimeEvents.NewSafroleTickets) async throws {
        // Safrole VRF commitments only changes every epoch
        // and we should never receive tickets at very beginning and very end of an epoch
        // so it is safe to use best head state without worrying about forks or edge cases
        let state = try await blockchain.getState(hash: blockchain.bestHead)
        guard let state else {
            try throwUnreachable("no state for best head")
        }

        try await storage.update(state: state, config: blockchain.config, tickets: tickets.items)
    }

    private func on(blockFinalized event: RuntimeEvents.BlockFinalized) async throws {
        let block = try await blockchain.getBlock(hash: event.hash)
        guard let block else {
            try throwUnreachable("no block for finalized head")
        }
        await storage.removeTickets(tickets: block.extrinsic.tickets.tickets.array)
    }

    public var pendingTickets: SortedArray<TicketItemAndOutput> {
        get async {
            await storage.pendingTickets
        }
    }
}
