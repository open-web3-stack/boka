import Foundation
import Testing
import TracingUtils
import Utils

@testable import Blockchain

struct ValidatorServiceTests {
    func setup(time: TimeInterval = 988) async throws -> (BlockchainServices, ValidatorService) {
        // setupTestLogger()

        let services = await BlockchainServices(
            timeProvider: MockTimeProvider(time: time)
        )
        let validatorService = await ValidatorService(
            blockchain: services.blockchain(),
            keystore: services.keystore,
            eventBus: services.eventBus,
            scheduler: services.scheduler,
            dataProvider: services.dataProvider
        )
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
        #expect(scheduler.storage.value.tasks.count > 0)
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
        #expect(dataProvider.bestHead == block.hash)

        // Check block is stored in database
        #expect(try await dataProvider.hasBlock(hash: block.hash))
        #expect(try await dataProvider.getBlock(hash: block.hash) == block)
        _ = try await dataProvider.getState(hash: block.hash) // check can get state
        #expect(try await dataProvider.getHeads().contains(block.hash))
    }

    // try different genesis time offset to ensure edge cases are covered
    @Test(arguments: [988, 1000, 1003, 1020])
    func makeManyBlocks(time: Int) async throws {
        let (services, validatorService) = try await setup(time: TimeInterval(time))
        let genesisState = services.genesisState
        let storeMiddleware = services.storeMiddleware
        let config = services.config
        let scheduler = services.scheduler

        await validatorService.on(genesis: genesisState)

        await storeMiddleware.wait()

        await scheduler.advance(by: TimeInterval(config.value.slotPeriodSeconds) * 25 - 1)

        let events = await storeMiddleware.wait()

        let blockAuthoredEvents = events.filter { $0 is RuntimeEvents.BlockAuthored }

        #expect(blockAuthoredEvents.count == 25)
    }
}
