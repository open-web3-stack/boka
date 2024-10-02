import Codec
import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "BlockAuthor")

public final class BlockAuthor: ServiceBase2, @unchecked Sendable {
    private let blockchain: Blockchain
    private let keystore: KeyStore
    private let extrinsicPool: ExtrinsicPoolService

    private var tickets: ThreadSafeContainer<[RuntimeEvents.SafroleTicketsGenerated]> = .init([])

    public init(
        blockchain: Blockchain,
        eventBus: EventBus,
        keystore: KeyStore,
        scheduler: Scheduler,
        extrinsicPool: ExtrinsicPoolService
    ) async {
        self.blockchain = blockchain
        self.keystore = keystore
        self.extrinsicPool = extrinsicPool

        super.init(blockchain.config, eventBus, scheduler)

        await subscribe(RuntimeEvents.SafroleTicketsGenerated.self) { [weak self] event in
            try await self?.on(safroleTicketsGenerated: event)
        }
    }

    private func scheduleForNextEpoch() async {
        let now = timeProvider.getTimeslot()
        let nextEpoch = now.timeslotToEpochIndex(config: config) + 1
        let timeslot = nextEpoch.epochToTimeslotIndex(config: config)

        // at end of an epoch, try to determine the block author of next epoch
        // and schedule new block task
        schedule(at: timeslot - 1) { [weak self] in
            if let self {
                await onBeforeEpoch(timeslot: timeslot)
                await scheduleForNextEpoch()
            }
        }
    }

    public func on(genesis state: StateRef) async {
        await scheduleNewBlocks(ticketsOrKeys: state.value.safroleState.ticketsOrKeys)
        await scheduleForNextEpoch()
    }

    public func createNewBlock(claim: Either<(TicketItemAndOutput, Bandersnatch.PublicKey), Bandersnatch.PublicKey>) async throws
        -> BlockRef
    {
        let parentHash = blockchain.bestHead
        let state = try await blockchain.getState(hash: parentHash)
        guard let state else {
            try throwUnreachable("no state for best head")
        }

        let extrinsic = Extrinsic.dummy(config: config)

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

        let timeslot = timeProvider.getTimeslot()

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
                    entropy: vrfOutput,
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

    private func newBlock(claim: Either<(TicketItemAndOutput, Bandersnatch.PublicKey), Bandersnatch.PublicKey>) async {
        await withSpan("BlockAuthor.newBlock", logger: logger) { _ in
            let block = try await createNewBlock(claim: claim)
            logger.info("New block created: \(block.hash)")
            await publish(RuntimeEvents.BlockAuthored(block: block))
        }
    }

    private func on(safroleTicketsGenerated event: RuntimeEvents.SafroleTicketsGenerated) async throws {
        tickets.write { $0.append(event) }
    }

    private func onBeforeEpoch(timeslot: TimeslotIndex) async {
        await withSpan("BlockAuthor.onBeforeEpoch", logger: logger) { _ in
            tickets.value = []

            let bestHead = blockchain.bestHead
            let state = try await blockchain.getState(hash: bestHead)
            guard let state else {
                try throwUnreachable("no state for best head")
            }

            // simulate next block to determine the block authors for next epoch
            let res = try state.value.updateSafrole(
                config: config,
                slot: timeslot,
                entropy: Data32(),
                offenders: [],
                extrinsics: .dummy(config: config)
            )

            await scheduleNewBlocks(ticketsOrKeys: res.state.ticketsOrKeys)
        }
    }

    private func scheduleNewBlocks(ticketsOrKeys: SafroleTicketsOrKeys) async {
        let selfTickets = tickets.value
        let now = timeProvider.getTimeslot()
        let epochBase = now.timeslotToEpochIndex(config: config)
        let timeslotBase = epochBase.epochToTimeslotIndex(config: config)
        switch ticketsOrKeys {
        case let .left(tickets):
            if selfTickets.isEmpty {
                return
            }
            for (idx, ticket) in tickets.enumerated() {
                if let claim = selfTickets.first(withOutput: ticket.id) {
                    let timeslot = timeslotBase + TimeslotIndex(idx)
                    if timeslot <= now {
                        continue
                    }
                    logger.info("Scheduling new block task at timeslot \(timeslot))")
                    schedule(at: timeslot) { [weak self] in
                        if let self {
                            await newBlock(claim: .left(claim))
                        }
                    }
                }
            }
        case let .right(keys):
            for (idx, key) in keys.enumerated() {
                let pubkey = try? Bandersnatch.PublicKey(data: key)
                if let pubkey, await keystore.contains(publicKey: pubkey) {
                    let timeslot = timeslotBase + TimeslotIndex(idx)
                    if timeslot <= now {
                        continue
                    }
                    logger.info("Scheduling new block task at timeslot \(timeslot))")
                    schedule(at: timeslot) { [weak self] in
                        if let self {
                            await newBlock(claim: .right(pubkey))
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
