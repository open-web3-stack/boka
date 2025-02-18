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
        var allWorkPackages = [WorkPackageRef]()
        for i in 0 ..< 5 {
            let workpackage = WorkPackage.dummy(config: services.config) {
                $0.parameterizationBlob = Data([UInt8(i)])
            }.asRef()
            allWorkPackages.append(workpackage)
        }
        await services.eventBus.publish(RuntimeEvents.WorkPackagesReceived(items: allWorkPackages))
        let workPackages = await workPackagecPoolService.getPendingPackages()
        #expect(Set(workPackages) == Set(allWorkPackages))

        let workpackage = WorkPackage.dummy(config: services.config) {
            $0.parameterizationBlob = Data([UInt8(5)])
        }.asRef()
        await services.eventBus.publish(RuntimeEvents.WorkPackagesReceived(items: [workpackage]))

        #expect(await workPackagecPoolService.getPendingPackages().count == 6)

        let report = WorkReport.dummy(config: services.config) {
            $0.packageSpecification.workPackageHash = workpackage.hash
        }
        await services.eventBus.publish(RuntimeEvents.WorkReportGenerated(items: [report]))

        #expect(await workPackagecPoolService.getPendingPackages().count == 5)
    }
}
