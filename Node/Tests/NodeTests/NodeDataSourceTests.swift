import Blockchain
import Codec
import Foundation
@testable import Node
import Testing
import Utils

struct NodeDataSourceTests {
    let dataSource: NodeDataSource
    let networkManager: NetworkManager
    let network: MockNetwork
    let storeMiddleware: StoreMiddleware
    let services: BlockchainServices

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
            devPeers: [],
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
            name: "NodeDataSourceTests",
        )
    }

    @Test func submitWorkPackage() async throws {
        let workPackage = WorkPackage.dummy(config: services.config)
        let extrinsic = [Data([0, 1, 2]), Data([3, 4, 5])]
        try await dataSource.submitWorkPackage(coreIndex: 0, workPackage: JamEncoder.encode(workPackage), extrinsics: extrinsic)
        var observedWorkPackageEvent: RuntimeEvents.WorkPackagesSubmitted?
        for _ in 0 ..< 50 {
            let events = await storeMiddleware.wait()
            if let event = events.first(where: { $0 is RuntimeEvents.WorkPackagesSubmitted }) as? RuntimeEvents.WorkPackagesSubmitted {
                observedWorkPackageEvent = event
                break
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        let workPackageEvent = try #require(observedWorkPackageEvent)
        #expect(workPackageEvent.coreIndex == 0)
        #expect(workPackageEvent.workPackage.value == workPackage)
        #expect(workPackageEvent.extrinsics == extrinsic)

        // Wait for event processing
        await storeMiddleware.wait()
    }

    @Test func createKey() async throws {
        let blsKey = try await dataSource.create(keyType: .BLS)
        let ed25519Key = try await dataSource.create(keyType: .Ed25519)
        let bandersnatchKey = try await dataSource.create(keyType: .Bandersnatch)

        #expect(blsKey.key.count > 0)
        #expect(ed25519Key.key.count > 0)
        #expect(bandersnatchKey.key.count > 0)
        await storeMiddleware.wait()
    }

    @Test func listKeys() async throws {
        let blsKey = try await dataSource.create(keyType: .BLS)
        let ed25519Key = try await dataSource.create(keyType: .Ed25519)
        let bandersnatchKey = try await dataSource.create(keyType: .Bandersnatch)

        let keys = try await dataSource.listKeys()
        #expect(keys.contains { item in
            item.key == blsKey.key
        })
        #expect(keys.contains { item in
            item.key == ed25519Key.key
        })
        #expect(keys.contains { item in
            item.key == bandersnatchKey.key
        })
        await storeMiddleware.wait()
    }

    @Test func hasKey() async throws {
        let blsKey = try await dataSource.create(keyType: .BLS)
        let ed25519Key = try await dataSource.create(keyType: .Ed25519)
        let bandersnatchKey = try await dataSource.create(keyType: .Bandersnatch)

        let blsKeyData = try #require(Data(fromHexString: blsKey.key))
        let ed25519KeyData = try #require(Data(fromHexString: ed25519Key.key))
        let bandersnatchKeyData = try #require(Data(fromHexString: bandersnatchKey.key))

        let hasBLSKey = try await dataSource.has(keyType: .BLS, with: blsKeyData)

        let hasEd25519Key = try await dataSource.has(keyType: .Ed25519, with: ed25519KeyData)
        let hasBandersnatchKey = try await dataSource.has(keyType: .Bandersnatch, with: bandersnatchKeyData)

        #expect(hasBLSKey == true)
        #expect(hasEd25519Key == true)
        #expect(hasBandersnatchKey == true)

        let randomData = Data32.random().data
        let hasRandomKey = try await dataSource.has(keyType: .Bandersnatch, with: randomData)
        #expect(hasRandomKey == false)
        await storeMiddleware.wait()
    }
}
