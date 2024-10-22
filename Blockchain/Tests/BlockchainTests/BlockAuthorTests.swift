import Foundation
import Testing
import TracingUtils
import Utils

@testable import Blockchain

struct BlockAuthorTests {
    let config: ProtocolConfigRef
    let timeProvider: MockTimeProvider
    let dataProvider: BlockchainDataProvider
    let eventBus: EventBus
    let scheduler: MockScheduler
    let keystore: KeyStore
    let blockAuthor: BlockAuthor
    let runtime: Runtime
    let storeMiddleware: StoreMiddleware

    init() async throws {
        // setupTestLogger()

        config = ProtocolConfigRef.dev
        timeProvider = MockTimeProvider(time: 988)

        let (genesisState, genesisBlock) = try State.devGenesis(config: config)
        dataProvider = try await BlockchainDataProvider(InMemoryDataProvider(genesisState: genesisState, genesisBlock: genesisBlock))

        storeMiddleware = StoreMiddleware()
        eventBus = EventBus(eventMiddleware: .serial(Middleware(storeMiddleware), .noError), handlerMiddleware: .noError)

        scheduler = MockScheduler(timeProvider: timeProvider)

        keystore = try await DevKeyStore(devKeysCount: config.value.totalNumberOfValidators)

        blockAuthor = await BlockAuthor(
            config: config,
            dataProvider: dataProvider,
            eventBus: eventBus,
            keystore: keystore,
            scheduler: scheduler,
            extrinsicPool: ExtrinsicPoolService(config: config, dataProvider: dataProvider, eventBus: eventBus)
        )

        runtime = Runtime(config: config)
    }

    @Test
    func createNewBlockWithFallbackKey() async throws {
        let genesisState = try await dataProvider.getState(hash: dataProvider.genesisBlockHash)

        let timeslot = timeProvider.getTime().timeToTimeslot(config: config)

        // get the validator key
        let idx = timeslot % UInt32(config.value.totalNumberOfValidators)
        let devKey = try DevKeyStore.getDevKey(seed: idx)

        // Create a new block
        let block = try await blockAuthor.createNewBlock(timeslot: timeslot, claim: .right(devKey.bandersnatch))

        // Verify block
        try _ = runtime.apply(block: block, state: genesisState, context: .init(timeslot: timeslot + 1))
    }

    @Test
    func createNewBlockWithTicket() async throws {
        let genesisState = try await dataProvider.getState(hash: dataProvider.genesisBlockHash)
        var state = genesisState.value

        state.safroleState.ticketsVerifier = try Bandersnatch.RingCommitment(
            ring: state.currentValidators.map { try Bandersnatch.PublicKey(data: $0.bandersnatch) },
            ctx: Bandersnatch.RingContext(size: UInt(config.value.totalNumberOfValidators))
        ).data

        let timeslot = timeProvider.getTime().timeToTimeslot(config: config)

        // get the validator key
        let idx = timeslot % UInt32(config.value.epochLength)
        let devKey = try DevKeyStore.getDevKey(seed: idx % UInt32(config.value.totalNumberOfValidators))
        let secretKey = await keystore.get(Bandersnatch.self, publicKey: devKey.bandersnatch)!

        let ticket = try SafroleService.generateTickets(
            count: 1,
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
        try await dataProvider.add(state: newStateRef)

        // Create a new block
        let block = try await blockAuthor.createNewBlock(timeslot: timeslot, claim: .left((ticket, devKey.bandersnatch)))

        // Verify block
        try _ = runtime.apply(block: block, state: newStateRef, context: .init(timeslot: timeslot + 1))
    }

    @Test
    func firstBlock() async throws {
        let genesisState = try await dataProvider.getState(hash: dataProvider.genesisBlockHash)

        await blockAuthor.on(genesis: genesisState)

        #expect(scheduler.storage.value.tasks.count > 0)

        // await scheduler.advance(by: 2)

        let events = await storeMiddleware.wait()
        #expect(events.count == 1)
        #expect(events.first is RuntimeEvents.BlockAuthored)

        let block = events.first as! RuntimeEvents.BlockAuthored

        let timeslot = timeProvider.getTime().timeToTimeslot(config: config)

        // Verify block
        try _ = runtime.apply(block: block.block, state: genesisState, context: .init(timeslot: timeslot + 1))
    }

    // TODO: test including extrinsic tickets from extrinsic pool
    // TODO: test when ticketsAccumulator is full
    // TODO: test when none of the items in pool are smaller enough
}
