import Codec
import Foundation
import Synchronization
import TracingUtils
import Utils

/// Service for authoring new blocks in the blockchain
///
/// Thread-safety: @unchecked Sendable is safe here because:
/// - Inherits safety from ServiceBase2 (immutable properties + ThreadSafeContainer)
/// - tickets property is protected by ThreadSafeContainer
/// - All other properties are immutable (let)
public final class BlockAuthor: ServiceBase2, @unchecked Sendable, OnBeforeEpoch {
    private let dataProvider: BlockchainDataProvider
    private let keystore: KeyStore
    private let safroleTicketPool: SafroleTicketPoolService

    private let tickets: ThreadSafeContainer<[RuntimeEvents.SafroleTicketsGenerated]> = .init([])

    public init(
        config: ProtocolConfigRef,
        dataProvider: BlockchainDataProvider,
        eventBus: EventBus,
        keystore: KeyStore,
        scheduler: Scheduler,
        safroleTicketPool: SafroleTicketPoolService
    ) async {
        self.dataProvider = dataProvider
        self.keystore = keystore
        self.safroleTicketPool = safroleTicketPool

        super.init(id: "BlockAuthor", config: config, eventBus: eventBus, scheduler: scheduler)

        await subscribe(RuntimeEvents.SafroleTicketsGenerated.self, id: "BlockAuthor.SafroleTicketsGenerated") { [weak self] event in
            try await self?.on(safroleTicketsGenerated: event)
        }
    }

    public func createNewBlock(
        timeslot: TimeslotIndex,
        claim: Either<(TicketItemAndOutput, Bandersnatch.PublicKey), Bandersnatch.PublicKey>
    ) async throws -> BlockRef {
        let parentHash = await dataProvider.bestHead.hash

        logger.trace("creating new block for timeslot: \(timeslot) with parent hash: \(parentHash)")

        // Note: Block author verification happens at the call site (e.g., in checkSlot)
        // This method assumes the caller has already verified we are the author for this timeslot

        let state = try await dataProvider.getState(hash: parentHash)
        let stateRoot = await state.value.stateRoot
        let epoch = timeslot.timeslotToEpochIndex(config: config)
        let parentEpoch = state.value.timeslot.timeslotToEpochIndex(config: config)
        let isEpochChange = epoch > parentEpoch

        let pendingTickets = await safroleTicketPool.getPendingTickets(epoch: epoch)
        let existingTickets = SortedArray(sortedUnchecked: state.value.safroleState.ticketsAccumulator.array.map(\.id))
        let tickets = pendingTickets.array
            .lazy
            .filter { ticket in
                !existingTickets.contains(ticket.output)
            }
            .trimmingPrefix { ticket in
                guard let last = existingTickets.array.last else {
                    return true
                }
                return ticket.output < last
            }
            .prefix(config.value.maxTicketsPerExtrinsic)
            .map(\.ticket)

        let extrinsic = try Extrinsic(
            tickets: ExtrinsicTickets(tickets: ConfigLimitedSizeArray(config: config, array: Array(tickets))),
            disputes: ExtrinsicDisputes.dummy(config: config), // Disputes included in this block
            preimages: ExtrinsicPreimages.dummy(config: config), // Preimage revelations
            availability: ExtrinsicAvailability.dummy(config: config), // Availability votes/claims
            reports: ExtrinsicGuarantees.dummy(config: config) // Work report guarantees
        )

        let (ticket, publicKey): (TicketItemAndOutput?, Bandersnatch.PublicKey) = switch claim {
        case let .left((ticket, publicKey)):
            (ticket, publicKey)
        case let .right(publicKey):
            (nil, publicKey)
        }

        guard let secretKey = await keystore.get(Bandersnatch.self, publicKey: publicKey) else {
            try throwUnreachable("no secret key for public key")
        }

        let sealEntropy = isEpochChange ? state.value.entropyPool.t2 : state.value.entropyPool.t3

        let vrfOutput: Data32
        if let ticket {
            vrfOutput = ticket.output
        } else {
            let inputData = SigningContext.fallbackSealInputData(entropy: sealEntropy)
            vrfOutput = try secretKey.getOutput(vrfInputData: inputData)
        }

        let vrfSignature = try secretKey.ietfVRFSign(vrfInputData: SigningContext.entropyInputData(entropy: vrfOutput))

        let authorIndex = state.value.currentValidators.firstIndex { publicKey.data == $0.bandersnatch }
        guard let authorIndex else {
            try throwUnreachable("author not in current validator")
        }

        let safroleResult = try state.value.updateSafrole(
            config: config,
            slot: timeslot,
            entropy: Bandersnatch.getIetfSignatureOutput(signature: vrfSignature),
            offenders: state.value.judgements.punishSet,
            extrinsics: extrinsic.tickets
        )

        let unsignedHeader = Header.Unsigned(
            parentHash: parentHash,
            priorStateRoot: stateRoot,
            extrinsicsHash: extrinsic.hash(),
            timeslot: timeslot,
            epoch: safroleResult.epochMark,
            winningTickets: safroleResult.ticketsMark,
            authorIndex: ValidatorIndex(authorIndex),
            vrfSignature: vrfSignature,
            offendersMarkers: [] // Judged offenders who will be marked in this block
        )

        let encodedHeader = try JamEncoder.encode(unsignedHeader)

        let seal = if let ticket {
            try secretKey.ietfVRFSign(
                vrfInputData: SigningContext.safroleTicketInputData(
                    entropy: sealEntropy,
                    attempt: ticket.ticket.attempt
                ),
                auxData: encodedHeader
            )
        } else {
            try secretKey.ietfVRFSign(
                vrfInputData: SigningContext.fallbackSealInputData(entropy: sealEntropy),
                auxData: encodedHeader
            )
        }

        let header = Header(
            unsigned: unsignedHeader,
            seal: seal
        )
        let block = Block(header: header, extrinsic: extrinsic)
        return BlockRef(block)
    }

    private func newBlock(
        timeslot: TimeslotIndex,
        claim: Either<(TicketItemAndOutput, Bandersnatch.PublicKey), Bandersnatch.PublicKey>
    ) async {
        await withSpan("BlockAuthor.newBlock", logger: logger) { _ in
            // Note: Block creation should complete within a single timeslot
            // Consider adding timeout if needed for production
            let block = try await createNewBlock(timeslot: timeslot, claim: claim)
            logger.debug("New block created: #\(block.header.timeslot) \(block.hash) on parent #\(block.header.parentHash)")
            publish(RuntimeEvents.BlockAuthored(block: block))
        }
    }

    private func on(safroleTicketsGenerated event: RuntimeEvents.SafroleTicketsGenerated) async throws {
        tickets.write { $0.append(event) }
    }

    public func onBeforeEpoch(epoch: EpochIndex, safroleState: SafrolePostState) async {
        logger.debug("scheduling new blocks for epoch \(epoch)")
        await withSpan("BlockAuthor.onBeforeEpoch", logger: logger) { _ in
            tickets.value = []
            let timeslot = epoch.epochToTimeslotIndex(config: config)

            let bestHead = await dataProvider.bestHead

            let bestHeadTimeslot = bestHead.timeslot
            let bestHeadEpoch = bestHeadTimeslot.timeslotToEpochIndex(config: config)
            if bestHeadEpoch != 0, bestHeadEpoch + 1 < epoch {
                logger.warning("best head epoch \(bestHeadEpoch) is too far from current epoch \(epoch)")
            } else if bestHeadEpoch >= epoch {
                logger.error("trying to do onBeforeEpoch for epoch \(epoch) but best head epoch is \(bestHeadEpoch)")
            }

            logger.trace("expected safrole tickets", metadata: [
                "tickets": "\(safroleState.ticketsOrKeys)", "epoch": "\(epoch)", "parentTimeslot": "\(bestHead.timeslot)",
            ])

            await scheduleNewBlocks(ticketsOrKeys: safroleState.ticketsOrKeys, timeslot: timeslot)
        }
    }

    private func scheduleNewBlocks(ticketsOrKeys: SafroleTicketsOrKeys, timeslot base: TimeslotIndex) async {
        let selfTickets = tickets.value
        let epochBase = base.timeslotToEpochIndex(config: config)
        let timeslotBase = epochBase.epochToTimeslotIndex(config: config)
        let now = timeProvider.getTimeInterval()
        switch ticketsOrKeys {
        case let .left(tickets):
            if selfTickets.isEmpty {
                return
            }
            for (idx, ticket) in tickets.enumerated() {
                if let claim = selfTickets.first(withOutput: ticket.id) {
                    let timeslot = timeslotBase + TimeslotIndex(idx)
                    let time = config.scheduleTimeForAuthoring(timeslot: timeslot)
                    let delay = time - now
                    if delay < 0 {
                        continue
                    }
                    logger.trace("Scheduling new block task at timeslot \(timeslot) for claim \(claim.1.data.toHexString())")
                    schedule(id: "BlockAuthor.newBlock", delay: delay) { [weak self] in
                        if let self {
                            await newBlock(timeslot: timeslot, claim: .left(claim))
                        }
                    }
                }
            }
        case let .right(keys):
            for (idx, key) in keys.enumerated() {
                let pubkey = try? Bandersnatch.PublicKey(data: key)
                if let pubkey, await keystore.contains(publicKey: pubkey) {
                    let timeslot = timeslotBase + TimeslotIndex(idx)
                    let time = config.scheduleTimeForAuthoring(timeslot: timeslot)
                    let delay = time - now
                    if delay < 0 {
                        continue
                    }
                    logger.trace("Scheduling new block task at timeslot \(timeslot) for key \(pubkey.data.toHexString())")
                    schedule(id: "BlockAuthor.newBlock", delay: delay) { [weak self] in
                        if let self {
                            await newBlock(timeslot: timeslot, claim: .right(pubkey))
                        }
                    }
                }
            }
        }
    }
}

extension [RuntimeEvents.SafroleTicketsGenerated] {
    func first(withOutput output: Data32) -> (TicketItemAndOutput, Bandersnatch.PublicKey)? {
        for item in self {
            if let ticket = item.items.first(where: { $0.output == output }) {
                return (ticket, item.publicKey)
            }
        }
        return nil
    }
}
