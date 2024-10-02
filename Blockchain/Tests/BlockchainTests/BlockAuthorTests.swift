import Testing
import TracingUtils
import Utils

@testable import Blockchain

struct BlockAuthorTests {
    let config: ProtocolConfigRef
    let timeProvider: MockTimeProvider
    let eventBus: EventBus
    let blockchain: Blockchain
    let scheduler: MockScheduler
    let blockAuthor: BlockAuthor
    let runtime: Runtime
    let storeMiddleware: StoreMiddleware

    init() async throws {
        config = ProtocolConfigRef.dev
        timeProvider = MockTimeProvider(slotPeriodSeconds: UInt32(config.value.slotPeriodSeconds), time: 1000)

        let dataProvider = try await InMemoryDataProvider(genesis: StateRef(State.devGenesis(config: config)))

        storeMiddleware = StoreMiddleware()
        eventBus = EventBus(eventMiddleware: Middleware(storeMiddleware))

        blockchain = try await Blockchain(
            config: config,
            dataProvider: dataProvider,
            timeProvider: timeProvider,
            eventBus: eventBus
        )

        scheduler = MockScheduler(timeProvider: timeProvider)

        blockAuthor = try await BlockAuthor(
            blockchain: blockchain,
            eventBus: eventBus,
            keystore: DevKeyStore(devKeysCount: config.value.totalNumberOfValidators),
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
    func testScheduleNewBlocks() async throws {
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
