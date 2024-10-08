import Foundation
import Testing
import TracingUtils
import Utils

@testable import Blockchain

struct ValidatorServiceTests {
    let config: ProtocolConfigRef
    let timeProvider: MockTimeProvider
    let dataProvider: BlockchainDataProvider
    let eventBus: EventBus
    let scheduler: MockScheduler
    let keystore: KeyStore
    let validatorService: ValidatorService
    let storeMiddleware: StoreMiddleware

    init() async throws {
        setupTestLogger()

        config = ProtocolConfigRef.dev
        timeProvider = MockTimeProvider(time: 988)

        dataProvider = try await BlockchainDataProvider(InMemoryDataProvider(genesis: StateRef(State.devGenesis(config: config))))

        storeMiddleware = StoreMiddleware()
        eventBus = EventBus(eventMiddleware: Middleware(storeMiddleware))

        scheduler = MockScheduler(timeProvider: timeProvider)

        keystore = try await DevKeyStore(devKeysCount: config.value.totalNumberOfValidators)

        let blockchain = try await Blockchain(
            config: config,
            dataProvider: dataProvider,
            timeProvider: timeProvider,
            eventBus: eventBus
        )

        validatorService = await ValidatorService(
            blockchain: blockchain,
            keystore: keystore,
            eventBus: eventBus,
            scheduler: scheduler,
            dataProvider: dataProvider
        )
    }

    @Test
    func onGenesis() async throws {
        let genesisState = try await dataProvider.getState(hash: Data32())

        await validatorService.on(genesis: genesisState)

        let events = await storeMiddleware.wait()

        // Check if SafroleTicketsGenerated events were published
        let safroleEvents = events.filter { $0 is RuntimeEvents.SafroleTicketsGenerated }
        #expect(safroleEvents.count == config.value.totalNumberOfValidators)

        // Check if block author tasks were scheduled
        #expect(scheduler.storage.value.tasks.count > 0)
    }

    @Test
    func produceBlocks() async throws {
        let genesisState = try await dataProvider.getState(hash: Data32())

        await validatorService.on(genesis: genesisState)

        // Advance time to trigger block production
        await scheduler.advance(by: TimeInterval(config.value.slotPeriodSeconds))

        let events = await storeMiddleware.wait()

        // Check if a BlockAuthored event was published
        let blockAuthoredEvent = events.last { $0 is RuntimeEvents.BlockAuthored }
        #expect(blockAuthoredEvent != nil)

        let blockEvent = blockAuthoredEvent as! RuntimeEvents.BlockAuthored
        // Verify the produced block
        let block = blockEvent.block
        // we produce block before the timeslot starts
        #expect(block.header.timeslot == timeProvider.getTime().timeToTimeslot(config: config) + 1)
        #expect(block.header.parentHash == genesisState.value.lastBlockHash)

        // Check if the block author is one of the validators
        let authorIndex = Int(block.header.authorIndex)

        let authorKey = genesisState.value.currentValidators[authorIndex]
        let publicKey = try Bandersnatch.PublicKey(data: authorKey.bandersnatch)
        #expect(await keystore.contains(publicKey: publicKey))

        // Check the blockchain head is updated
        #expect(dataProvider.bestHead == block.hash)

        // Check block is stored in database
        #expect(try await dataProvider.hasBlock(hash: block.hash))
        #expect(try await dataProvider.getBlock(hash: block.hash) == block)
        _ = try await dataProvider.getState(hash: block.hash) // check can get state
        #expect(try await dataProvider.getHeads().contains(block.hash))
    }

    @Test
    func makeManyBlocks() async throws {
        let genesisState = try await dataProvider.getState(hash: Data32())

        await validatorService.on(genesis: genesisState)

        await scheduler.advance(by: TimeInterval(config.value.slotPeriodSeconds) * 20)

        let events = await storeMiddleware.wait()

        let blockAuthoredEvents = events.filter { $0 is RuntimeEvents.BlockAuthored }

        #expect(blockAuthoredEvents.count == 21)
    }
}
