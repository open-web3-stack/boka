import Foundation
import Testing
import TracingUtils
import Utils

@testable import Blockchain

struct ValidatorServiceTests {
    func setup(
        config: ProtocolConfigRef = .dev,
        time: TimeInterval = 988,
        keysCount: Int = 12
    ) async throws -> (BlockchainServices, ValidatorService) {
        // setupTestLogger()

        let services = await BlockchainServices(
            config: config,
            timeProvider: MockTimeProvider(time: time),
            keysCount: keysCount
        )
        let validatorService = await ValidatorService(
            blockchain: services.blockchain,
            keystore: services.keystore,
            eventBus: services.eventBus,
            scheduler: services.scheduler,
            dataProvider: services.dataProvider
        )
        await validatorService.onSyncCompleted()
        return (services, validatorService)
    }

    @Test
    func onGenesis() async throws {
        let (services, validatorService) = try await setup()
        let genesisState = services.genesisState
        let storeMiddleware = services.storeMiddleware
        let config = services.config
        let scheduler = services.scheduler

        await validatorService.on(genesis: genesisState)

        let events = await storeMiddleware.wait()

        // Check if SafroleTicketsGenerated events were published
        let safroleEvents = events.filter { $0 is RuntimeEvents.SafroleTicketsGenerated }
        #expect(safroleEvents.count == config.value.totalNumberOfValidators)

        // Check if block author tasks were scheduled
        #expect(scheduler.taskCount > 0)
    }

    @Test
    func produceBlocks() async throws {
        let (services, validatorService) = try await setup()
        let genesisState = services.genesisState
        let storeMiddleware = services.storeMiddleware
        let config = services.config
        let scheduler = services.scheduler
        let timeProvider = services.timeProvider
        let keystore = services.keystore
        let dataProvider = services.dataProvider

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
        #expect(await dataProvider.bestHead.hash == block.hash)

        // Check block is stored in database
        #expect(try await dataProvider.hasBlock(hash: block.hash))
        #expect(try await dataProvider.getBlock(hash: block.hash) == block)
        _ = try await dataProvider.getState(hash: block.hash) // check can get state
        #expect(try await dataProvider.getHeads().contains(block.hash))
    }

    // try different genesis time offset to ensure edge cases are covered
    @Test(arguments: [988, 1000, 1003, 1021])
    func makeManyBlocksWithAllKeys(time: Int) async throws {
        let (services, validatorService) = try await setup(time: TimeInterval(time))
        let genesisState = services.genesisState
        let storeMiddleware = services.storeMiddleware
        let config = services.config
        let scheduler = services.scheduler

        await validatorService.on(genesis: genesisState)

        await storeMiddleware.wait()

        for _ in 0 ..< 25 {
            await scheduler.advance(by: TimeInterval(config.value.slotPeriodSeconds))
            await storeMiddleware.wait() // let events to be processed
        }

        let events = await storeMiddleware.wait()

        let blockAuthoredEvents = events.filter { $0 is RuntimeEvents.BlockAuthored }

        #expect(blockAuthoredEvents.count == 25)
    }

    @Test
    func makeManyBlocksWithSingleKey() async throws {
        let (services, validatorService) = try await setup(
            config: .minimal,
            keysCount: 0
        )
        let genesisState = services.genesisState
        let storeMiddleware = services.storeMiddleware
        let config = services.config
        let scheduler = services.scheduler
        let keystore = services.keystore

        try await keystore.addDevKeys(seed: 0)

        await validatorService.on(genesis: genesisState)

        await storeMiddleware.wait()

        for _ in 0 ..< 50 {
            await scheduler.advance(by: TimeInterval(config.value.slotPeriodSeconds))
            await storeMiddleware.wait() // let events to be processed
        }

        let events = await storeMiddleware.wait()

        let blockAuthoredEvents = events.filter { $0 is RuntimeEvents.BlockAuthored }

        #expect(blockAuthoredEvents.count > 0)
    }
}
