import Blockchain
import Codec
@testable import RPC
import Testing
import TracingUtils
import Utils
import Vapor
import XCTVapor

actor DummyKeystoreDataSource {
    var keys: [PubKeyItem] = []
    func addKey(_ key: PubKeyItem) {
        keys.append(key)
    }
}

extension DummyKeystoreDataSource: KeystoreDataSource {
    func create(keyType: CreateKeyType) async throws -> String {
        let publicKey = "\(keyType.rawValue)_PublicKey_\(UUID().uuidString)"
        let item = PubKeyItem(key: publicKey, type: keyType.rawValue)
        keys.append(item)
        return publicKey
    }

    public func listKeys() async throws -> [PubKeyItem] {
        keys
    }

    public func hasKey(publicKey: Data) async throws -> Bool {
        keys.contains { item in
            Data(item.key.utf8) == publicKey
        }
    }
}

final class KeyStoreRPCControllerTests {
    let app: Application
    let dummyKeystoreDataSource = DummyKeystoreDataSource()

    init() async throws {
        app = try await Application.make(.testing)
        let rpcController = JSONRPCController(handlers: KeystoreHandlers.getHandlers(source: dummyKeystoreDataSource))
        try app.register(collection: rpcController)
    }

    @Test
    func createKey() async throws {
        let keyType = CreateKeyType.BLS.rawValue
        let params = JSON.array([.string(Data(keyType.utf8).toHexString())])

        let req = JSONRequest(jsonrpc: "2.0", method: "keys_create", params: params, id: 0)
        var buffer = ByteBuffer()
        try buffer.writeJSONEncodable(req)
        try await app.test(.POST, "/", headers: ["Content-Type": "application/json"], body: buffer) { res async in
            #expect(res.status == .ok)
            let resp = try? res.content.decode(JSONResponse.self, using: JSONDecoder())
            #expect(resp?.result?.value != nil)
            if let publicKey = resp?.result?.value as? String {
                let keys = await self.dummyKeystoreDataSource.keys
                #expect(keys.contains { item in
                    item.key == publicKey
                })
            }
        }

        let keys = await dummyKeystoreDataSource.keys
        #expect(keys.count == 1)
        try await app.asyncShutdown()
    }

    @Test
    func listKeys() async throws {
        let item1 = PubKeyItem(key: "PublicKey_1", type: CreateKeyType.BLS.rawValue)
        let item2 = PubKeyItem(key: "PublicKey_2", type: CreateKeyType.Ed25519.rawValue)

        await dummyKeystoreDataSource.addKey(item1)
        await dummyKeystoreDataSource.addKey(item2)

        let req = JSONRequest(jsonrpc: "2.0", method: "keys_list", params: JSON.array([]), id: 0)
        var buffer = ByteBuffer()
        try buffer.writeJSONEncodable(req)
        try await app.test(.POST, "/", headers: ["Content-Type": "application/json"], body: buffer) { res async in
            #expect(res.status == .ok)
            let resp = try? res.content.decode(JSONResponse.self, using: JSONDecoder())
            if let keys = resp?.result?.value as? [PubKeyItem] {
                #expect(keys.count == 2)
                #expect(keys.contains { item in
                    item.key == item1.key
                })
                #expect(keys.contains { item in
                    item.key == item2.key
                })
            }
        }
        try await app.asyncShutdown()
    }

    @Test
    func hasKey() async throws {
        let item1 = PubKeyItem(key: "PublicKey_1", type: CreateKeyType.BLS.rawValue)

        let publicKeyString = Data(item1.key.utf8).toHexString()

        await dummyKeystoreDataSource.addKey(item1)

        let params = JSON.array([.string(publicKeyString)])

        let req = JSONRequest(jsonrpc: "2.0", method: "keys_hasKey", params: params, id: 0)
        var buffer = ByteBuffer()
        try buffer.writeJSONEncodable(req)
        try await app.test(.POST, "/", headers: ["Content-Type": "application/json"], body: buffer) { res async in
            #expect(res.status == .ok)
            let resp = try? res.content.decode(JSONResponse.self, using: JSONDecoder())
            #expect((resp?.result!.value as! Utils.JSON).bool == true)
        }
        try await app.asyncShutdown()
    }
}
