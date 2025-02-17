import Foundation
import Testing
import TracingUtils
import Utils

@testable import Blockchain

struct WorkPackagePoolServiceTests {
    func setup(
        config: ProtocolConfigRef = .dev,
        time: TimeInterval = 988,
        keysCount: Int = 12
    ) async throws -> (BlockchainServices, WorkPackagePoolService) {
        let services = await BlockchainServices(
            config: config,
            timeProvider: MockTimeProvider(time: time),
            keysCount: keysCount
        )
        let workPackagecPoolService = await WorkPackagePoolService(
            config: services.config,
            dataProvider: services.dataProvider,
            eventBus: services.eventBus
        )
        return (services, workPackagecPoolService)
    }

    @Test
    func testAddPendingWorkPackage() async throws {
        let (services, workPackagecPoolService) = try await setup()
        var allWorkPackages = [WorkPackage]()
        for _ in 0 ..< services.config.value.totalNumberOfCores {
            let workpackage = WorkPackage(
                authorizationToken: Data(),
                authorizationServiceIndex: 0,
                authorizationCodeHash: Data32.random(),
                parameterizationBlob: Data(),
                context: RefinementContext.dummy(config: services.config),
                workItems: try! ConfigLimitedSizeArray(config: services.config, defaultValue: WorkItem.dummy(config: services.config))
            )
            allWorkPackages.append(workpackage)
        }
        await services.eventBus.publish(RuntimeEvents.WorkPackagesReceived(items: allWorkPackages))
        let workPackages = await workPackagecPoolService.getWorkPackages()
        #expect(workPackages.array == Array(allWorkPackages).sorted())
        let workpackage = WorkPackage.dummy(config: services.config)
        try await workPackagecPoolService.addWorkPackages(packages: [workpackage])
        try await workPackagecPoolService.removeWorkPackages(packages: [workpackage])
        #expect(workPackages.array.count == services.config.value.totalNumberOfCores)
    }
}
