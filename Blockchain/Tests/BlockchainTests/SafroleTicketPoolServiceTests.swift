@testable import Blockchain
import Foundation
import Testing
import TracingUtils
import Utils

struct SafroleTicketPoolServiceTests {
    let config: ProtocolConfigRef
    let timeProvider: MockTimeProvider
    let dataProvider: BlockchainDataProvider
    let eventBus: EventBus
    let keystore: KeyStore
    let storeMiddleware: StoreMiddleware
    let poolService: SafroleTicketPoolService
    let ringContext: Bandersnatch.RingContext

    init() async throws {
        config = ProtocolConfigRef.dev.mutate { config in
            config.ticketEntriesPerValidator = 4
        }
        timeProvider = MockTimeProvider(time: 1000)

        let (genesisState, genesisBlock) = try State.devGenesis(config: config)
        dataProvider = try await BlockchainDataProvider(InMemoryDataProvider(genesisState: genesisState, genesisBlock: genesisBlock))

        let logger = Logger(label: "SafroleTicketPoolServiceTests")
        storeMiddleware = StoreMiddleware()
        let logMiddleware = LogMiddleware(logger: logger, propagateError: true)
        eventBus = EventBus(
            eventMiddleware: .serial(Middleware(storeMiddleware), Middleware(logMiddleware)),
            handlerMiddleware: Middleware(logMiddleware),
        )

        keystore = try await DevKeyStore(devKeysCount: config.value.totalNumberOfValidators)

        poolService = await SafroleTicketPoolService(config: config, dataProvider: dataProvider, eventBus: eventBus)

        ringContext = try Bandersnatch.RingContext(size: UInt(config.value.totalNumberOfValidators))

        // setupTestLogger()
    }

    @Test
    func addAndRetrieveTickets() async throws {
        let state = try await dataProvider.getBestState()

        var allTickets = SortedUniqueArray<TicketItemAndOutput>()

        for (i, validatorKey) in state.value.nextValidators.enumerated() {
            let secretKey: Bandersnatch.SecretKey = try await #require(keystore.get(
                Bandersnatch.self,
                publicKey: Bandersnatch.PublicKey(data: validatorKey.bandersnatch),
            ))

            let tickets = try SafroleService.generateTickets(
                count: TicketIndex(config.value.ticketEntriesPerValidator),
                validators: state.value.nextValidators.array,
                entropy: state.value.entropyPool.t3,
                ringContext: ringContext,
                secret: secretKey,
                idx: UInt32(i),
            )

            allTickets.append(contentsOf: tickets)

            let event = RuntimeEvents.SafroleTicketsGenerated(
                epochIndex: state.value.timeslot.timeslotToEpochIndex(config: config),
                items: tickets,
                publicKey: secretKey.publicKey,
            )
            await eventBus.publish(event)

            // Wait for the event to be processed
            await storeMiddleware.wait()

            let pendingTickets = await poolService
                .getPendingTickets(epoch: state.value.timeslot.timeslotToEpochIndex(config: config))
            #expect(pendingTickets == allTickets)
        }
    }

    @Test
    func addAndInvalidTickets() async throws {
        let state = try await dataProvider.getBestState()

        var allTickets = SortedUniqueArray<TicketItemAndOutput>()

        let validatorKey = state.value.currentValidators[0]
        let secretKey = try await #require(keystore.get(
            Bandersnatch.self,
            publicKey: Bandersnatch.PublicKey(data: validatorKey.bandersnatch),
        ))

        var tickets = try SafroleService.generateTickets(
            count: TicketIndex(config.value.ticketEntriesPerValidator) + 2,
            validators: state.value.nextValidators.array,
            entropy: state.value.entropyPool.t3,
            ringContext: ringContext,
            secret: secretKey,
            idx: 0,
        )

        tickets.append(tickets[0]) // duplicate

        let invalidTicket = TicketItemAndOutput(
            ticket: ExtrinsicTickets.TicketItem(
                attempt: 0,
                signature: Data784(),
            ),
            output: Data32(),
        )
        tickets.append(invalidTicket)

        allTickets.append(contentsOf: tickets[..<config.value.ticketEntriesPerValidator]) // only valid tickets

        let event = RuntimeEvents.SafroleTicketsReceived(items: tickets.map(\.ticket))
        await eventBus.publish(event)
        await eventBus.publish(event) // duplicate

        // Wait for the event to be processed
        await storeMiddleware.wait()

        let pendingTickets = await poolService.getPendingTickets(epoch: state.value.timeslot.timeslotToEpochIndex(config: config))
        #expect(pendingTickets == allTickets)
    }

    @Test
    func removeTicketsOnBlockFinalization() async throws {
        // Add some tickets to the pool
        let state: StateRef = try await dataProvider.getBestState()
        let validatorKey = state.value.currentValidators[0]
        let secretKey = try await #require(keystore.get(
            Bandersnatch.self,
            publicKey: Bandersnatch.PublicKey(data: validatorKey.bandersnatch),
        ))

        let tickets = try SafroleService.generateTickets(
            count: 4,
            validators: state.value.currentValidators.array,
            entropy: state.value.entropyPool.t3,
            ringContext: ringContext,
            secret: secretKey,
            idx: 0,
        )

        let addEvent = RuntimeEvents.SafroleTicketsGenerated(
            epochIndex: state.value.timeslot.timeslotToEpochIndex(config: config),
            items: tickets,
            publicKey: secretKey.publicKey,
        )
        await eventBus.publish(addEvent)

        // Wait for the event to be processed
        await storeMiddleware.wait()

        // Create a block with some of these tickets
        let blockTickets = Array(tickets[0 ..< 2])
        let extrinsic = try Extrinsic(
            tickets: ExtrinsicTickets(tickets: ConfigLimitedSizeArray(config: config, array: blockTickets.map(\.ticket))),
            disputes: ExtrinsicDisputes.dummy(config: config),
            preimages: ExtrinsicPreimages.dummy(config: config),
            availability: ExtrinsicAvailability.dummy(config: config),
            reports: ExtrinsicGuarantees.dummy(config: config),
        )
        let block = BlockRef(Block(header: Header.dummy(config: config), extrinsic: extrinsic)).mutate {
            $0.header.unsigned.parentHash = state.value.lastBlockHash
            $0.header.unsigned.timeslot = state.value.timeslot + 1
        }

        try await dataProvider.add(block: block)

        // Finalize the block
        let finalizeEvent = RuntimeEvents.BlockFinalized(hash: block.hash)
        await eventBus.publish(finalizeEvent)

        // Wait for the event to be processed
        await storeMiddleware.wait()

        // Check that the tickets in the block have been removed from the pool
        let pendingTickets = await poolService.getPendingTickets(epoch: state.value.timeslot.timeslotToEpochIndex(config: config))
        #expect(pendingTickets.array == Array(tickets[2 ..< 4]).sorted())
    }

    @Test
    func updateStateOnEpochChange() async throws {
        // Insert some valid tickets
        let state = try await dataProvider.getBestState()
        let validatorKey = state.value.currentValidators[0]
        let secretKey = try await #require(keystore.get(
            Bandersnatch.self,
            publicKey: Bandersnatch.PublicKey(data: validatorKey.bandersnatch),
        ))

        let oldTickets = try SafroleService.generateTickets(
            count: 4,
            validators: state.value.currentValidators.array,
            entropy: state.value.entropyPool.t3,
            ringContext: ringContext,
            secret: secretKey,
            idx: 0,
        )

        let addEvent = RuntimeEvents.SafroleTicketsGenerated(
            epochIndex: state.value.timeslot.timeslotToEpochIndex(config: config),
            items: oldTickets,
            publicKey: secretKey.publicKey,
        )
        await eventBus.publish(addEvent)
        await storeMiddleware.wait()

        let epoch = state.value.timeslot.timeslotToEpochIndex(config: config)

        #expect(await poolService.getPendingTickets(epoch: epoch).count == 4)
        #expect(await poolService.getPendingTickets(epoch: epoch + 1).count == 0)

        // Simulate an epoch change with new entropy
        let nextTimeslot = state.value.timeslot + TimeslotIndex(config.value.epochLength)

        let bestHead = await dataProvider.bestHead.hash
        let newBlock = BlockRef.dummy(config: config).mutate {
            $0.header.unsigned.timeslot = nextTimeslot
            $0.header.unsigned.parentHash = bestHead
        }

        let oldEntropyPool = state.value.entropyPool
        let newEntropyPool = EntropyPool((Data32.random(), oldEntropyPool.t0, oldEntropyPool.t1, oldEntropyPool.t2))
        let newState = try state.mutate {
            $0.entropyPool = newEntropyPool
            $0.timeslot = nextTimeslot
            try $0.recentHistory.items.append(RecentHistory.HistoryItem(
                headerHash: newBlock.hash,
                superPeak: Data32(),
                stateRoot: Data32(),
                lookup: .init(),
            ))
        }

        try await dataProvider.blockImported(block: newBlock, state: newState)

        // Generate new tickets
        let newTickets = try SafroleService.generateTickets(
            count: 4,
            validators: newState.value.currentValidators.array,
            entropy: newState.value.entropyPool.t3,
            ringContext: ringContext,
            secret: secretKey,
            idx: 0,
        )

        // Ensure new tickets are accepted
        let newAddEvent = RuntimeEvents.SafroleTicketsGenerated(
            epochIndex: newState.value.timeslot.timeslotToEpochIndex(config: config),
            items: newTickets,
            publicKey: secretKey.publicKey,
        )
        await eventBus.publish(newAddEvent)
        await storeMiddleware.wait()

        let finalPendingTickets = await poolService.getPendingTickets(epoch: epoch + 1)
        #expect(finalPendingTickets.array == newTickets.sorted())

        #expect(await poolService.getPendingTickets(epoch: epoch).count == 0)
        #expect(await poolService.getPendingTickets(epoch: epoch + 2).count == 0)
    }
}
