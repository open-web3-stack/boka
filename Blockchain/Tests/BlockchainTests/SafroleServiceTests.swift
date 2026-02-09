@testable import Blockchain
import Foundation
import Testing
import TracingUtils
import Utils

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

        let logger = Logger(label: "SafroleServiceTests")
        storeMiddleware = StoreMiddleware()
        let logMiddleware = LogMiddleware(logger: logger, propagateError: true)
        eventBus = EventBus(
            eventMiddleware: .serial(Middleware(storeMiddleware), Middleware(logMiddleware)),
            handlerMiddleware: Middleware(logMiddleware),
        )
        keystore = try await DevKeyStore(devKeysCount: 2)

        safroleService = await SafroleService(config: config, eventBus: eventBus, keystore: keystore)

        ringContext = try Bandersnatch.RingContext(size: UInt(config.value.totalNumberOfValidators))

        await safroleService.onSyncCompleted()

        // setupTestLogger()
    }

    @Test
    func generateTicketsOnGenesis() async throws {
        await safroleService.on(genesis: genesisState)

        let events = await storeMiddleware.wait()
        #expect(events.count == 2)

        for event in events {
            #expect(event is RuntimeEvents.SafroleTicketsGenerated)
            let ticketEvent = try #require(event as? RuntimeEvents.SafroleTicketsGenerated)
            #expect(ticketEvent.items.count == config.value.ticketEntriesPerValidator)
        }
    }

    @Test
    func generateTicketsOnEpochChange() async throws {
        // Simulate an epoch change
        let newBlock = BlockRef.dummy(config: config).mutate {
            $0.header.unsigned.timeslot += TimeslotIndex(config.value.epochLength)
        }

        let newState = try genesisState.mutate {
            $0.timeslot = newBlock.header.timeslot
            try $0.recentHistory.items.append(RecentHistory.HistoryItem(
                headerHash: newBlock.hash,
                superPeak: Data32(),
                stateRoot: Data32(),
                lookup: .init(),
            ))
        }

        await eventBus.publish(RuntimeEvents.BlockImported(block: newBlock, state: newState, parentState: genesisState))

        let events = await storeMiddleware.wait()
        #expect(events.count == 3) // first event is BlockImported

        for event in events[1...] {
            #expect(event is RuntimeEvents.SafroleTicketsGenerated)
            let ticketEvent = try #require(event as? RuntimeEvents.SafroleTicketsGenerated)
            #expect(ticketEvent.items.count == config.value.ticketEntriesPerValidator)
        }
    }

    @Test
    func noTicketGenerationMidEpoch() async throws {
        // Simulate a mid-epoch block
        let newBlock = BlockRef.dummy(config: config).mutate {
            $0.header.unsigned.timeslot += 1
        }

        let newState = try genesisState.mutate {
            $0.timeslot = newBlock.header.timeslot
            try $0.recentHistory.items.append(RecentHistory.HistoryItem(
                headerHash: newBlock.hash,
                superPeak: Data32(),
                stateRoot: Data32(),
                lookup: .init(),
            ))
        }

        await eventBus.publish(RuntimeEvents.BlockImported(block: newBlock, state: newState, parentState: genesisState))

        let events = await storeMiddleware.wait()
        #expect(events.count == 1)
    }
}
