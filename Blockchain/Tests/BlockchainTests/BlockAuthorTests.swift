import Foundation
import Testing
import TracingUtils
import Utils

@testable import Blockchain

struct BlockAuthorTests {
    func setup() async -> (BlockchainServices, BlockAuthor, Runtime) {
        // setupTestLogger()

        let services = await BlockchainServices()
        let blockAuthor = await services.blockAuthor
        let runtime = Runtime(config: services.config)
        return (services, blockAuthor, runtime)
    }

    @Test
    func createNewBlockWithFallbackKey() async throws {
        let (services, blockAuthor, runtime) = await setup()
        let config = services.config
        let timeProvider = services.timeProvider
        let genesisState = services.genesisState

        let timeslot = timeProvider.getTime().timeToTimeslot(config: config)

        // dry run Safrole to get the validator key
        let res = try genesisState.value.updateSafrole(
            config: config,
            slot: timeslot,
            entropy: Data32(),
            offenders: [],
            extrinsics: .dummy(config: config)
        )

        let idx = timeslot % UInt32(config.value.epochLength)
        let key = res.state.ticketsOrKeys.right!.array[Int(idx)]
        let pubkey = try! Bandersnatch.PublicKey(data: key)

        // Create a new block
        let block = try await blockAuthor.createNewBlock(timeslot: timeslot, claim: .right(pubkey))

        // Verify block
        try _ = runtime.apply(block: block, state: genesisState, context: .init(timeslot: timeslot + 1))
    }

    @Test
    func createNewBlockWithTicket() async throws {
        let (services, blockAuthor, runtime) = await setup()
        let config = services.config
        let timeProvider = services.timeProvider
        let genesisState = services.genesisState
        let keystore = services.keystore
        let dataProvider = services.dataProvider

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
        state.timeslot = timeslot - 1

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
        let (services, blockAuthor, runtime) = await setup()
        let config = services.config
        let timeProvider = services.timeProvider
        let genesisState = services.genesisState
        let scheduler = services.scheduler
        let storeMiddleware = services.storeMiddleware

        await blockAuthor.on(genesis: genesisState)

        #expect(scheduler.storage.value.tasks.count > 0)

        await scheduler.advance(by: TimeInterval(2))

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
