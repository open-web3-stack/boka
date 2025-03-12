import Blockchain
import Codec
import Foundation
import Testing
import Utils

@testable import Node

struct NodeDataSourceTests {
    let dataSource: NodeDataSource
    let networkManager: NetworkManagerTests
    init() async throws {
        networkManager = try! await NetworkManagerTests()
        dataSource = await NodeDataSource(
            blockchain: networkManager.services.blockchain,
            chainDataProvider: networkManager.services.dataProvider,
            networkManager: networkManager.networkManager,
            name: "submitWorkPackage"
        )
    }

    @Test func submitWorkPackage() async throws {
        let workPackage = WorkPackage.dummy(config: networkManager.services.config)
        let extrinsic = [Data([0, 1, 2]), Data([3, 4, 5])]
        try await dataSource.submitWorkPackage(coreIndex: 0, workPackage: JamEncoder.encode(workPackage), extrinsics: extrinsic)
        let events = await networkManager.storeMiddleware.wait()

        #expect(events.count == 1)
        #expect(events[0] is RuntimeEvents.WorkPackagesSubmitted)

        let workPackageEvent = events[0] as! RuntimeEvents.WorkPackagesSubmitted
        #expect(workPackageEvent.coreIndex == 0)
        #expect(workPackageEvent.workPackage.value == workPackage)
        #expect(workPackageEvent.extrinsics == extrinsic)
    }
}
