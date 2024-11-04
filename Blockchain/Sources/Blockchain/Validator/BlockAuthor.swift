import Codec
import Foundation
import Synchronization
import TracingUtils
import Utils

public final class BlockAuthor: ServiceBase2, @unchecked Sendable {
    private let dataProvider: BlockchainDataProvider
    private let keystore: KeyStore
    private let extrinsicPool: ExtrinsicPoolService

    private let tickets: ThreadSafeContainer<[RuntimeEvents.SafroleTicketsGenerated]> = .init([])

    public init(
        config: ProtocolConfigRef,
        dataProvider: BlockchainDataProvider,
        eventBus: EventBus,
        keystore: KeyStore,
        scheduler: Scheduler,
        extrinsicPool: ExtrinsicPoolService
    ) async {
        self.dataProvider = dataProvider
        self.keystore = keystore
        self.extrinsicPool = extrinsicPool

        super.init(id: "BlockAuthor", config: config, eventBus: eventBus, scheduler: scheduler)

        await subscribe(RuntimeEvents.SafroleTicketsGenerated.self, id: "BlockAuthor.SafroleTicketsGenerated") { [weak self] event in
            try await self?.on(safroleTicketsGenerated: event)
        }
    }

    public func onSyncCompleted() async {
        scheduleForNextEpoch("BlockAuthor.scheduleForNextEpoch") { [weak self] epoch in
            await self?.onBeforeEpoch(epoch: epoch)
        }
    }

    public func on(genesis _: StateRef) async {
        let nowTimeslot = timeProvider.getTime().timeToTimeslot(config: config)
        // schedule for current epoch
        let epoch = nowTimeslot.timeslotToEpochIndex(config: config)
        await onBeforeEpoch(epoch: epoch)
    }

    public func createNewBlock(
        timeslot: TimeslotIndex,
        claim: Either<(TicketItemAndOutput, Bandersnatch.PublicKey), Bandersnatch.PublicKey>
    ) async throws -> BlockRef {
        let parentHash = await dataProvider.bestHead.hash

        logger.trace("creating new block for timeslot: \(timeslot) with parent hash: \(parentHash)")

        // TODO: verify we are indeed the block author

        let state = try await dataProvider.getState(hash: parentHash)
        let epoch = timeslot.timeslotToEpochIndex(config: config)

        let pendingTickets = await extrinsicPool.getPendingTickets(epoch: epoch)
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
            judgements: ExtrinsicDisputes.dummy(config: config), // TODO:
            preimages: ExtrinsicPreimages.dummy(config: config), // TODO:
            availability: ExtrinsicAvailability.dummy(config: config), // TODO:
            reports: ExtrinsicGuarantees.dummy(config: config) // TODO:
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

        let vrfOutput: Data32
        if let ticket {
            vrfOutput = ticket.output
        } else {
            let inputData = SigningContext.fallbackSealInputData(entropy: state.value.entropyPool.t3)
            vrfOutput = try secretKey.getOutput(vrfInputData: inputData)
        }

        let vrfSignature = if ticket != nil {
            try secretKey.ietfVRFSign(vrfInputData: SigningContext.entropyInputData(entropy: vrfOutput))
        } else {
            try secretKey.ietfVRFSign(vrfInputData: SigningContext.fallbackSealInputData(entropy: state.value.entropyPool.t3))
        }

        let authorIndex = state.value.currentValidators.firstIndex { publicKey.data == $0.bandersnatch }
        guard let authorIndex else {
            try throwUnreachable("author not in current validator")
        }

        let safroleResult = try state.value.updateSafrole(
            config: config,
            slot: timeslot,
            entropy: state.value.entropyPool.t0,
            offenders: state.value.judgements.punishSet,
            extrinsics: extrinsic.tickets
        )

        let unsignedHeader = Header.Unsigned(
            parentHash: parentHash,
            priorStateRoot: state.stateRoot,
            extrinsicsHash: extrinsic.hash(),
            timeslot: timeslot,
            epoch: safroleResult.epochMark,
            winningTickets: safroleResult.ticketsMark,
            offendersMarkers: [], // TODO:
            authorIndex: ValidatorIndex(authorIndex),
            vrfSignature: vrfSignature
        )

        let encodedHeader = try JamEncoder.encode(unsignedHeader)

        let seal = if let ticket {
            try secretKey.ietfVRFSign(
                vrfInputData: SigningContext.safroleTicketInputData(
                    entropy: state.value.entropyPool.t3,
                    attempt: ticket.ticket.attempt
                ),
                auxData: encodedHeader
            )
        } else {
            try secretKey.ietfVRFSign(
                vrfInputData: SigningContext.fallbackSealInputData(entropy: state.value.entropyPool.t3),
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
            // TODO: add timeout
            let block = try await createNewBlock(timeslot: timeslot, claim: claim)
            logger.info("New block created: #\(block.header.timeslot) \(block.hash) on parent #\(block.header.parentHash)")
            publish(RuntimeEvents.BlockAuthored(block: block))
        }
    }

    private func on(safroleTicketsGenerated event: RuntimeEvents.SafroleTicketsGenerated) async throws {
        tickets.write { $0.append(event) }
    }

    private func onBeforeEpoch(epoch: EpochIndex) async {
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

            let state = try await dataProvider.getState(hash: bestHead.hash)

            // simulate next block to determine the block authors for next epoch
            let res = try state.value.updateSafrole(
                config: config,
                slot: timeslot,
                entropy: Data32(),
                offenders: [],
                extrinsics: .dummy(config: config)
            )

            logger.trace("expected safrole tickets", metadata: [
                "tickets": "\(res.state.ticketsOrKeys)", "epoch": "\(epoch)", "parentTimeslot": "\(bestHead.timeslot)",
            ])

            await scheduleNewBlocks(ticketsOrKeys: res.state.ticketsOrKeys, timeslot: timeslot)
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
