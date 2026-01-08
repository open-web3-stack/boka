import Foundation
import TracingUtils
import Utils

public struct TicketItemAndOutput: Comparable, Sendable, Codable {
    public let ticket: ExtrinsicTickets.TicketItem
    public let output: Data32

    public init(ticket: ExtrinsicTickets.TicketItem, output: Data32) {
        self.ticket = ticket
        self.output = output
    }

    public static func < (lhs: TicketItemAndOutput, rhs: TicketItemAndOutput) -> Bool {
        lhs.output < rhs.output
    }

    public static func == (lhs: TicketItemAndOutput, rhs: TicketItemAndOutput) -> Bool {
        lhs.output == rhs.output && lhs.ticket == rhs.ticket
    }
}

/// Service for managing Safrole protocol operations including ticket generation
///
/// Thread-safety: @unchecked Sendable is safe here because:
/// - Inherits safety from ServiceBase (immutable properties + actors)
/// - All properties are immutable (let)
/// - No mutable shared state beyond base class
public final class SafroleService: ServiceBase, @unchecked Sendable, OnGenesis, OnSyncCompleted {
    private let keystore: KeyStore
    private let ringContext: Bandersnatch.RingContext

    public init(
        config: ProtocolConfigRef,
        eventBus: EventBus,
        keystore: KeyStore
    ) async {
        self.keystore = keystore
        ringContext = try! Bandersnatch.RingContext(size: UInt(config.value.totalNumberOfValidators))

        super.init(id: "SafroleService", config: config, eventBus: eventBus)
    }

    public func on(genesis: StateRef) async {
        await withSpan("on(genesis)", logger: logger) { _ in
            try await generateAndSubmitTickets(state: genesis)
        }
    }

    public func onSyncCompleted() async {
        await subscribe(RuntimeEvents.BlockImported.self, id: "SafroleService.BlockImported") { [weak self] event in
            try await self?.on(blockImported: event)
        }
    }

    private func on(blockImported event: RuntimeEvents.BlockImported) async throws {
        if event.isNewEpoch(config: config) {
            logger.debug("generating tickets for epoch \(event.state.value.timeslot.timeslotToEpochIndex(config: config))")
            try await generateAndSubmitTickets(state: event.state)
        }
    }

    private func generateAndSubmitTickets(state: StateRef) async throws {
        let events = try await generateTicketEvents(state: state)
        for event in events {
            publish(event)
        }
    }

    private func generateTicketEvents(state: StateRef) async throws -> [RuntimeEvents.SafroleTicketsGenerated] {
        var events = [RuntimeEvents.SafroleTicketsGenerated]()

        for (idx, validator) in state.value.nextValidators.enumerated() {
            guard let pubkey = try? Bandersnatch.PublicKey(data: validator.bandersnatch) else {
                continue
            }

            guard let secret = await keystore.get(Bandersnatch.self, publicKey: pubkey) else {
                continue
            }

            try withSpan("generateTickets") { _ in
                let tickets = try SafroleService.generateTickets(
                    count: TicketIndex(config.value.ticketEntriesPerValidator),
                    validators: state.value.nextValidators.array,
                    entropy: state.value.entropyPool.t2,
                    ringContext: ringContext,
                    secret: secret,
                    idx: UInt32(idx)
                )

                events.append(.init(
                    epochIndex: state.value.timeslot.timeslotToEpochIndex(config: config),
                    items: tickets,
                    publicKey: secret.publicKey
                ))
            }
        }

        if events.isEmpty {
            logger.trace("Not in next validators")
        }

        return events
    }

    public static func generateTickets(
        count: TicketIndex,
        validators: [ValidatorKey],
        entropy: Data32,
        ringContext: Bandersnatch.RingContext,
        secret: Bandersnatch.SecretKey,
        idx: UInt32
    ) throws -> [TicketItemAndOutput] {
        let pubkeys = try validators.map {
            try Bandersnatch.PublicKey(data: $0.bandersnatch)
        }

        let prover = Bandersnatch.Prover(sercret: secret, ring: pubkeys, proverIdx: UInt(idx), ctx: ringContext)

        var vrfInputData = SigningContext.safroleTicketInputData(entropy: entropy, attempt: 0)

        var tickets: [TicketItemAndOutput] = []

        for i in 0 ..< count {
            vrfInputData[vrfInputData.count - 1] = TicketIndex(i)
            let sig = try prover.ringVRFSign(vrfInputData: vrfInputData)
            let out = try secret.getOutput(vrfInputData: vrfInputData)
            tickets.append(.init(ticket: .init(attempt: TicketIndex(i), signature: sig), output: out))
        }

        return tickets
    }
}
