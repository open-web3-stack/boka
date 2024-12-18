import Foundation
import Testing
import TracingUtils
import Utils

@testable import Blockchain

struct WorkPackagePoolServiceTests {
    let config: ProtocolConfigRef
    let timeProvider: MockTimeProvider
    let dataProvider: BlockchainDataProvider
    let eventBus: EventBus
    let keystore: KeyStore
    let storeMiddleware: StoreMiddleware
    let workPackagecPoolService: WorkPackagePoolService

    let ringContext: Bandersnatch.RingContext

    init() async throws {
        config = ProtocolConfigRef.dev.mutate { config in
            config.ticketEntriesPerValidator = 4
        }
        timeProvider = MockTimeProvider(time: 1000)

        let (genesisState, genesisBlock) = try State.devGenesis(config: config)
        dataProvider = try await BlockchainDataProvider(InMemoryDataProvider(genesisState: genesisState, genesisBlock: genesisBlock))

        storeMiddleware = StoreMiddleware()
        eventBus = EventBus(eventMiddleware: .serial(Middleware(storeMiddleware), .noError), handlerMiddleware: .noError)

        keystore = try await DevKeyStore(devKeysCount: config.value.totalNumberOfValidators)

        workPackagecPoolService = await WorkPackagePoolService(config: config, dataProvider: dataProvider, eventBus: eventBus)
        try await workPackagecPoolService.addWorkPackages(packages: [])
        ringContext = try Bandersnatch.RingContext(size: UInt(config.value.totalNumberOfValidators))

        // setupTestLogger()
    }

    @Test
    func testAddPendingWorkPackage() async throws {
        let state = try await dataProvider.getBestState()

        var allWorkPackages = SortedUniqueArray<WorkPackageAndOutput>()

        for (i, validatorKey) in state.value.nextValidators.enumerated() {
            let secretKey = try await keystore.get(Bandersnatch.self, publicKey: Bandersnatch.PublicKey(data: validatorKey.bandersnatch))!
            // generate work package
            // eventBus.publish
            // Wait for the event to be processed
            await storeMiddleware.wait()
        }
    }

    @Test
    func testAddAndInvalidWorkPackage() async throws {
        let state = try await dataProvider.getBestState()
        let validatorKey = state.value.currentValidators[0]
    }
}
