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
        config = ProtocolConfigRef.dev
        timeProvider = MockTimeProvider(time: 1000)

        let (genesisState, genesisBlock) = try State.devGenesis(config: config)
        dataProvider = try await BlockchainDataProvider(InMemoryDataProvider(genesisState: genesisState, genesisBlock: genesisBlock))

        storeMiddleware = StoreMiddleware()
        eventBus = EventBus(eventMiddleware: .serial(Middleware(storeMiddleware), .noError), handlerMiddleware: .noError)

        keystore = try await DevKeyStore(devKeysCount: config.value.totalNumberOfValidators)

        workPackagecPoolService = await WorkPackagePoolService(config: config, dataProvider: dataProvider, eventBus: eventBus)
        ringContext = try Bandersnatch.RingContext(size: UInt(config.value.totalNumberOfValidators))

        // setupTestLogger()
    }

    @Test
    func testAddPendingWorkPackage() async throws {
        var allWorkPackages = [WorkPackageAndOutput]()
        for _ in 0 ..< config.value.totalNumberOfCores {
            let workpackage = WorkPackage.dummy(config: config)
            let wpOut = WorkPackageAndOutput(workPackage: workpackage, output: Data32.random())
            allWorkPackages.append(wpOut)
        }
        await eventBus.publish(RuntimeEvents.WorkPackagesGenerated(items: allWorkPackages))
        await storeMiddleware.wait()
        let workPackages = await workPackagecPoolService.getWorkPackage()
        #expect(workPackages.array == Array(allWorkPackages).sorted())
        let workpackage = WorkPackage.dummy(config: config)
        let wpOut = WorkPackageAndOutput(workPackage: workpackage, output: Data32.random())
        try await workPackagecPoolService.addWorkPackages(packages: [wpOut])
        try await workPackagecPoolService.removeWorkPackages(packages: [wpOut])
        #expect(workPackages.array.count == config.value.totalNumberOfCores)
    }
}
