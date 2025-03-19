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
            keystore: InMemoryKeyStore(),
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

    @Test func createKey() async throws {
        let blsKey = try await dataSource.create(keyType: .BLS)
        let ed25519Key = try await dataSource.create(keyType: .Ed25519)
        let bandersnatchKey = try await dataSource.create(keyType: .Bandersnatch)

        #expect(blsKey.count > 0)
        #expect(ed25519Key.count > 0)
        #expect(bandersnatchKey.count > 0)
    }

    @Test func listKeys() async throws {
        let blsKey = try await dataSource.create(keyType: .BLS)
        let ed25519Key = try await dataSource.create(keyType: .Ed25519)
        let bandersnatchKey = try await dataSource.create(keyType: .Bandersnatch)

        let keys = try await dataSource.listKeys()
        #expect(keys.contains { item in
            item.key == blsKey
        })
        #expect(keys.contains { item in
            item.key == ed25519Key
        })
        #expect(keys.contains { item in
            item.key == bandersnatchKey
        })
    }

    @Test func hasKey() async throws {
        let blsKeyHex = try await dataSource.create(keyType: .BLS)
        let ed25519KeyHex = try await dataSource.create(keyType: .Ed25519)
        let bandersnatchKeyHex = try await dataSource.create(keyType: .Bandersnatch)

        let blsKeyData = Data(fromHexString: blsKeyHex)!
        let ed25519KeyData = Data(fromHexString: ed25519KeyHex)!
        let bandersnatchKeyData = Data(fromHexString: bandersnatchKeyHex)!

        let hasBLSKey = try await dataSource.has(keyType: .BLS, with: blsKeyData)

        let hasEd25519Key = try await dataSource.has(keyType: .Ed25519, with: ed25519KeyData)
        let hasBandersnatchKey = try await dataSource.has(keyType: .Bandersnatch, with: bandersnatchKeyData)

        #expect(hasBLSKey == true)
        #expect(hasEd25519Key == true)
        #expect(hasBandersnatchKey == true)

        let randomData = Data32.random().data
        let hasRandomKey = try await dataSource.has(keyType: .Bandersnatch, with: randomData)
        #expect(hasRandomKey == false)
    }
}
