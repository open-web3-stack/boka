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
            keystore: InMemoryKeyStore(),
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

    @Test func createKey() async throws {
        let blsKey = try await dataSource.createKey(keyType: .BLS)
        let ed25519Key = try await dataSource.createKey(keyType: .Ed25519)
        let bandersnatchKey = try await dataSource.createKey(keyType: .Bandersnatch)

        #expect(blsKey.count > 0)
        #expect(ed25519Key.count > 0)
        #expect(bandersnatchKey.count > 0)
    }

    @Test func listKeys() async throws {
        let blsKey = try await dataSource.createKey(keyType: .BLS)
        let ed25519Key = try await dataSource.createKey(keyType: .Ed25519)
        let bandersnatchKey = try await dataSource.createKey(keyType: .Bandersnatch)

        let keys = try await dataSource.listKeys()
        #expect(keys.contains(blsKey))
        #expect(keys.contains(ed25519Key))
        #expect(keys.contains(bandersnatchKey))
    }

    @Test func hasKey() async throws {
        let blsKeyHex = try await dataSource.createKey(keyType: .BLS)
        let ed25519KeyHex = try await dataSource.createKey(keyType: .Ed25519)
        let bandersnatchKeyHex = try await dataSource.createKey(keyType: .Bandersnatch)

        let blsKeyData = Data(fromHexString: blsKeyHex)!
        let ed25519KeyData = Data(fromHexString: ed25519KeyHex)!
        let bandersnatchKeyData = Data(fromHexString: bandersnatchKeyHex)!

        let hasBLSKey = try await dataSource.hasKey(publicKey: blsKeyData)
        let hasEd25519Key = try await dataSource.hasKey(publicKey: ed25519KeyData)
        let hasBandersnatchKey = try await dataSource.hasKey(publicKey: bandersnatchKeyData)

        #expect(hasBLSKey == true)
        #expect(hasEd25519Key == true)
        #expect(hasBandersnatchKey == true)

        let randomData = Data32.random().data
        let hasRandomKey = try await dataSource.hasKey(publicKey: randomData)
        #expect(hasRandomKey == false)
    }
}
