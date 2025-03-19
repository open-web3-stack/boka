import Blockchain
import Testing
import TracingUtils
import Vapor
import XCTVapor

@testable import RPC
@testable import Utils

actor DummyKeystoreDataSource {
    var createdKeys: [PubKeyItem] = []
    var hasKeyCalls: [(KeyGenType, Data)] = []
}

extension DummyKeystoreDataSource: KeystoreDataSource {
    public func create(keyType: KeyGenType) async throws -> PubKeyItem {
        let key = "dummyKey_\(keyType.rawValue)"
        let pubKeyItem = PubKeyItem(key: key, type: keyType.rawValue)
        createdKeys.append(pubKeyItem)
        return pubKeyItem
    }

    public func listKeys() async throws -> [PubKeyItem] {
        createdKeys
    }

    public func has(keyType _: KeyGenType, with publicKey: Data) async throws -> Bool {
        createdKeys.contains { $0.key == String(data: publicKey, encoding: .utf8) }
    }
}

final class KeystoreHandlersTests {
    let app: Application
    let dummyKeystoreDataSource = DummyKeystoreDataSource()

    init() async throws {
        app = try await Application.make(.testing)
        let rpcController = JSONRPCController(handlers: KeystoreHandlers.getHandlers(source: dummyKeystoreDataSource))
        try app.register(collection: rpcController)
    }

    @Test
    func createKey() async throws {
        let params = JSON.array([.string("ed25519")])
        let req = JSONRequest(jsonrpc: "2.0", method: "keys_create", params: params, id: 0)
        var buffer = ByteBuffer()
        try buffer.writeJSONEncodable(req)
        try await app.test(.POST, "/", headers: ["Content-Type": "application/json"], body: buffer) { res async in
            #expect(res.status == .ok)
            let resp = try? res.content.decode(JSONResponse.self, using: JSONDecoder())
            #expect(resp?.result!.value as? JSON != nil)
        }
        let createdKeys = await dummyKeystoreDataSource.createdKeys
        #expect(createdKeys.count == 1)
        #expect(createdKeys[0].key == "dummyKey_ed25519")
        #expect(createdKeys[0].type == "ed25519")
        try await app.asyncShutdown()
    }

    @Test
    func listKeys() async throws {
        _ = try await dummyKeystoreDataSource.create(keyType: .Ed25519)
        _ = try await dummyKeystoreDataSource.create(keyType: .BLS)

        let req = JSONRequest(jsonrpc: "2.0", method: "keys_list", params: .array([]), id: 0)
        var buffer = ByteBuffer()
        try buffer.writeJSONEncodable(req)
        try await app.test(.POST, "/", headers: ["Content-Type": "application/json"], body: buffer) { res async in
            #expect(res.status == .ok)
            let resp = try? res.content.decode(JSONResponse.self, using: JSONDecoder())
            #expect((resp?.result?.value as! JSON).array!.count >= 2)
        }
        try await app.asyncShutdown()
    }

    @Test
    func hasKey() async throws {
        let ed25519PubKey = try await dummyKeystoreDataSource.create(keyType: .Ed25519)

        let params = JSON.array([.string(ed25519PubKey.type), .string(ed25519PubKey.key.data(using: .utf8)!.toHexString())])
        let req = JSONRequest(jsonrpc: "2.0", method: "keys_hasKey", params: params, id: 0)
        var buffer = ByteBuffer()
        try buffer.writeJSONEncodable(req)
        try await app.test(.POST, "/", headers: ["Content-Type": "application/json"], body: buffer) { res async in
            #expect(res.status == .ok)
            let resp = try? res.content.decode(JSONResponse.self, using: JSONDecoder())
            #expect((resp?.result!.value as! JSON).bool == true)
        }
        try await app.asyncShutdown()
    }
}
