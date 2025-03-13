import Foundation
import Testing
import TracingUtils
import Utils

@testable import Blockchain

struct SafroleServiceTests {
    let config: ProtocolConfigRef
    let timeProvider: MockTimeProvider
    let eventBus: EventBus
    let keystore: KeyStore
    let storeMiddleware: StoreMiddleware
    let safroleService: SafroleService
    let ringContext: Bandersnatch.RingContext
    let genesisState: StateRef

    init() async throws {
        config = ProtocolConfigRef.dev.mutate { config in
            config.ticketEntriesPerValidator = 4
        }
        timeProvider = MockTimeProvider(time: 1000)

        (genesisState, _) = try State.devGenesis(config: config)

        storeMiddleware = StoreMiddleware()
        eventBus = EventBus(eventMiddleware: .serial(Middleware(storeMiddleware), .noError), handlerMiddleware: .noError)
        let tempDir = FileManager.default.temporaryDirectory
        let keyStoreDir = tempDir.appendingPathComponent("KeyStoreTests")
        try? FileManager.default.removeItem(at: keyStoreDir)
        keystore = try await DevKeyStore(devKeysCount: 2, .file(path: keyStoreDir))

        safroleService = await SafroleService(config: config, eventBus: eventBus, keystore: keystore)

        ringContext = try Bandersnatch.RingContext(size: UInt(config.value.totalNumberOfValidators))

        // setupTestLogger()
    }

    @Test
    func testGenerateTicketsOnGenesis() async throws {
        await safroleService.on(genesis: genesisState)

        let events = await storeMiddleware.wait()
        #expect(events.count == 2)

        for event in events {
            #expect(event is RuntimeEvents.SafroleTicketsGenerated)
            let ticketEvent = event as! RuntimeEvents.SafroleTicketsGenerated
            #expect(ticketEvent.items.count == config.value.ticketEntriesPerValidator)
        }
    }

    @Test
    func testGenerateTicketsOnEpochChange() async throws {
        // Simulate an epoch change
        let newBlock = BlockRef.dummy(config: config).mutate {
            $0.header.unsigned.timeslot += TimeslotIndex(config.value.epochLength)
        }

        let newState = try genesisState.mutate {
            $0.timeslot = newBlock.header.timeslot
            try $0.recentHistory.items.append(RecentHistory.HistoryItem(
                headerHash: newBlock.hash,
                mmr: MMR([]),
                stateRoot: Data32(),
                lookup: .init()
            ))
        }

        await eventBus.publish(RuntimeEvents.BlockImported(block: newBlock, state: newState, parentState: genesisState))

        let events = await storeMiddleware.wait()
        #expect(events.count == 3) // first event is BlockImported

        for event in events[1...] {
            #expect(event is RuntimeEvents.SafroleTicketsGenerated)
            let ticketEvent = event as! RuntimeEvents.SafroleTicketsGenerated
            #expect(ticketEvent.items.count == config.value.ticketEntriesPerValidator)
        }
    }

    @Test
    func testNoTicketGenerationMidEpoch() async throws {
        // Simulate a mid-epoch block
        let newBlock = BlockRef.dummy(config: config).mutate {
            $0.header.unsigned.timeslot += 1
        }

        let newState = try genesisState.mutate {
            $0.timeslot = newBlock.header.timeslot
            try $0.recentHistory.items.append(RecentHistory.HistoryItem(
                headerHash: newBlock.hash,
                mmr: MMR([]),
                stateRoot: Data32(),
                lookup: .init()
            ))
        }

        await eventBus.publish(RuntimeEvents.BlockImported(block: newBlock, state: newState, parentState: genesisState))

        let events = await storeMiddleware.wait()
        #expect(events.count == 1)
    }
}
