import Blockchain
import Foundation
import Testing
import Utils

@testable import Node

struct NodeDataSourceTests {
    var dataSource: NodeDataSource!
    var networkManager: NetworkManagerTests!
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
        let WorkPackageSubmissionMessage = WorkPackageSubmissionMessage(coreIndex: 0, workPackage: workPackage, extrinsics: [])
        #expect(try await dataSource.submitWorkPackage(data: WorkPackageSubmissionMessage.encode()) == true)
    }
}
