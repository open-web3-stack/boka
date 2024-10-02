import Foundation
import Testing
import TracingUtils
import Utils

@testable import Blockchain

struct BlockAuthorTests {
    let config: ProtocolConfigRef
    let timeProvider: MockTimeProvider
    let dataProvider: InMemoryDataProvider
    let eventBus: EventBus
    let blockchain: Blockchain
    let scheduler: MockScheduler
    let keystore: KeyStore
    let blockAuthor: BlockAuthor
    let runtime: Runtime
    let storeMiddleware: StoreMiddleware

    init() async throws {
        config = ProtocolConfigRef.dev
        timeProvider = MockTimeProvider(slotPeriodSeconds: UInt32(config.value.slotPeriodSeconds), time: 1000)

        dataProvider = try await InMemoryDataProvider(genesis: StateRef(State.devGenesis(config: config)))

        storeMiddleware = StoreMiddleware()
        eventBus = EventBus(eventMiddleware: Middleware(storeMiddleware))

        blockchain = try await Blockchain(
            config: config,
            dataProvider: dataProvider,
            timeProvider: timeProvider,
            eventBus: eventBus
        )

        scheduler = MockScheduler(timeProvider: timeProvider)

        keystore = try await DevKeyStore(devKeysCount: config.value.totalNumberOfValidators)

        blockAuthor = await BlockAuthor(
            blockchain: blockchain,
            eventBus: eventBus,
            keystore: keystore,
            scheduler: scheduler,
            extrinsicPool: ExtrinsicPoolService(blockchain: blockchain, eventBus: eventBus)
        )

        runtime = Runtime(config: config)

        setupTestLogger()
    }

    @Test
    func createNewBlockWithFallbackKey() async throws {
        let genesisState = try await blockchain.getState(hash: Data32())!

        // get the validator key
        let idx = scheduler.timeProvider.getTimeslot() % UInt32(config.value.totalNumberOfValidators)
        let devKey = try DevKeyStore.getDevKey(seed: idx)

        // Create a new block
        let block = try await blockAuthor.createNewBlock(claim: .right(devKey.bandersnatch))

        // Verify block
        try _ = runtime.apply(block: block, state: genesisState, context: .init(timeslot: timeProvider.getTimeslot() + 1))
    }

    @Test
    func createNewBlockWithTicket() async throws {
        let genesisState = try await blockchain.getState(hash: Data32())!
        var state = genesisState.value

        state.safroleState.ticketsVerifier = try Bandersnatch.RingCommitment(
            ring: state.currentValidators.map { try Bandersnatch.PublicKey(data: $0.bandersnatch) },
            ctx: Bandersnatch.RingContext(size: UInt(config.value.totalNumberOfValidators))
        ).data

        // get the validator key
        let idx = scheduler.timeProvider.getTimeslot() % UInt32(config.value.epochLength)
        let devKey = try DevKeyStore.getDevKey(seed: idx % UInt32(config.value.totalNumberOfValidators))
        let secretKey = await keystore.get(Bandersnatch.self, publicKey: devKey.bandersnatch)!

        let ticket = try SafroleService.generateTickets(
            count: TicketIndex(config.value.maxTicketsPerExtrinsic),
            validators: state.currentValidators.array,
            entropy: state.entropyPool.t2,
            ringContext: Bandersnatch.RingContext(size: UInt(config.value.totalNumberOfValidators)),
            secret: secretKey,
            idx: UInt32(idx)
        )[0]

        var validatorTickets = Array(repeating: Ticket.dummy(config: config), count: config.value.epochLength)

        validatorTickets[Int(idx)] = Ticket(
            id: ticket.output,
            attempt: ticket.ticket.attempt
        )

        state.safroleState.ticketsOrKeys = try .left(ConfigFixedSizeArray(config: config, array: validatorTickets))

        let newStateRef = StateRef(state)
        // modify genesis state
        await dataProvider.add(state: newStateRef)

        // Create a new block
        let block = try await blockAuthor.createNewBlock(claim: .left((ticket, devKey.bandersnatch)))

        // Verify block
        try _ = runtime.apply(block: block, state: newStateRef, context: .init(timeslot: timeProvider.getTimeslot() + 1))
    }

    @Test
    func scheduleNewBlocks() async throws {
        let genesisState = try await blockchain.getState(hash: Data32())!

        await blockAuthor.on(genesis: genesisState)

        #expect(scheduler.storage.value.tasks.count > 0)

        await scheduler.advance(by: 6)

        let events = await storeMiddleware.wait()
        #expect(events.count == 1)
        #expect(events.first is RuntimeEvents.BlockAuthored)

        let block = events.first as! RuntimeEvents.BlockAuthored

        // Verify block
        try _ = runtime.apply(block: block.block, state: genesisState, context: .init(timeslot: timeProvider.getTimeslot() + 1))
    }
}
