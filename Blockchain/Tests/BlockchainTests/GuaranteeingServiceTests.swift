import Foundation
import Testing
import TracingUtils
import Utils

@testable import Blockchain

struct GuaranteeingServiceTests {
    func createSimpleBlob() -> Data {
        let readOnlyLen: UInt32 = 256
        let readWriteLen: UInt32 = 512
        let heapPages: UInt16 = 4
        let stackSize: UInt32 = 1024
        let codeLength: UInt32 = 6

        let readOnlyData = Data(repeating: 0x01, count: Int(readOnlyLen))
        let readWriteData = Data(repeating: 0x02, count: Int(readWriteLen))
        let codeData = Data([0, 0, 2, 1, 2, 0])

        var blob = Data()
        blob.append(contentsOf: withUnsafeBytes(of: readOnlyLen.bigEndian) { Array($0.dropFirst(1)) })
        blob.append(contentsOf: withUnsafeBytes(of: readWriteLen.bigEndian) { Array($0.dropFirst(1)) })
        blob.append(contentsOf: withUnsafeBytes(of: heapPages.bigEndian) { Array($0) })
        blob.append(contentsOf: withUnsafeBytes(of: stackSize.bigEndian) { Array($0.dropFirst(1)) })
        blob.append(readOnlyData)
        blob.append(readWriteData)
        blob.append(contentsOf: Array(codeLength.encode(method: .fixedWidth(4))))
        blob.append(codeData)

        return blob
    }

    func setup(
        config: ProtocolConfigRef = .dev,
        time: TimeInterval = 988,
        keysCount: Int = 12
    ) async throws -> (BlockchainServices, GuaranteeingService) {
        let services = await BlockchainServices(
            config: config,
            timeProvider: MockTimeProvider(time: time),
            keysCount: keysCount
        )

        let extrinsicPoolService = await ExtrinsicPoolService(
            config: config,
            dataProvider: services.dataProvider,
            eventBus: services.eventBus
        )

        let runtime = Runtime(config: config)

        let guaranteeingService = await GuaranteeingService(
            config: config,
            eventBus: services.eventBus,
            scheduler: services.scheduler,
            dataProvider: services.dataProvider,
            keystore: services.keystore,
            runtime: runtime,
            extrinsicPool: extrinsicPoolService,
            dataStore: services.dataStore
        )
        return (services, guaranteeingService)
    }

    @Test func onGenesis() async throws {
        let (services, validatorService) = try await setup()
        let genesisState = services.genesisState
        let storeMiddleware = services.storeMiddleware
        let scheduler = services.scheduler

        var allWorkPackages = [WorkPackageAndOutput]()
        let blob = createSimpleBlob()
        for _ in 0 ..< services.config.value.totalNumberOfCores {
            let workpackage = WorkPackage(
                authorizationToken: Data(),
                authorizationServiceIndex: 0,
                authorizationCodeHash: Data32.random(),
                parameterizationBlob: blob,
                context: RefinementContext.dummy(config: services.config),
                workItems: try! ConfigLimitedSizeArray(config: services.config, defaultValue: WorkItem.dummy(config: services.config))
            )
            let wpOut = WorkPackageAndOutput(workPackage: workpackage, output: Data32.random())
            allWorkPackages.append(wpOut)
        }
        await services.eventBus.publish(RuntimeEvents.WorkPackagesGenerated(items: allWorkPackages))
        await validatorService.on(genesis: genesisState)
        await storeMiddleware.wait()
        #expect(scheduler.taskCount == 1)
    }
}
