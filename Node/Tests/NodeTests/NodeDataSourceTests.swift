import Blockchain
import Codec
import Foundation
import Testing
import Utils

@testable import Node

struct NodeDataSourceTests {
    let dataSource: NodeDataSource
    let networkManager: NetworkManager
    let network: MockNetwork
    let services: BlockchainServices
    let storeMiddleware: StoreMiddleware

    init() async throws {
        let services = await BlockchainServices()
        var network: MockNetwork!

        let networkManager = try await NetworkManager(
            buildNetwork: { handler in
                network = MockNetwork(handler: handler)
                return network
            },
            blockchain: services.blockchain,
            eventBus: services.eventBus,
            devPeers: []
        )

        self.networkManager = networkManager
        self.network = network
        self.services = services
        storeMiddleware = services.storeMiddleware

        dataSource = await NodeDataSource(
            blockchain: services.blockchain,
            chainDataProvider: services.dataProvider,
            networkManager: networkManager,
            name: "NodeDataSourceTests"
        )
    }

    @Test func submitWorkPackage() async throws {
        let workPackage = WorkPackage.dummy(config: services.config)
        let extrinsic = [Data([0, 1, 2]), Data([3, 4, 5])]
        try await dataSource.submitWorkPackage(coreIndex: 0, workPackage: JamEncoder.encode(workPackage), extrinsics: extrinsic)
        let events = await storeMiddleware.wait()

        #expect(events.count == 1)

        let workPackageEvent = try #require(events[0] as? RuntimeEvents.WorkPackagesSubmitted)
        #expect(workPackageEvent.coreIndex == 0)
        #expect(workPackageEvent.workPackage.value == workPackage)
        #expect(workPackageEvent.extrinsics == extrinsic)
    }
}
