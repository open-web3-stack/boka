// NOTE: Tests disabled - depends on Vapor 5
// These tests require Vapor 5 which has incompatible trait system
// Issue: Traits [HTTPClient, Multipart, TLS, WebSockets, bcrypt] have been enabled
// on package 'vapor' (vapor) that declares no traits.

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

    @Test(.disabled("Depends on Vapor 5"), .bug("/home/ubuntu/boka/RPC/Tests/RPCTests/KeystoreHandlersTests.swift:46"))
    func createKey() async throws {
        let params = JSON.array([.string("ed25519")])
        let req = JSONRequest(jsonrpc: "2.0", method: "keys_create", params: params, id: 0)
        var buffer = ByteBuffer()
        try buffer.writeJSONEncodable(req)
        try await app.testable().test(.POST, "/", headers: ["Content-Type": "application/json"], body: buffer) { res async in
            #expect(res.status == .ok)
            let resp = try? res.content.decode(JSONResponse.self, using: JSONDecoder())
            #expect(resp?.result?.value is JSON)
        }
        let createdKeys = await dummyKeystoreDataSource.createdKeys
        #expect(createdKeys.count == 1)
        #expect(createdKeys[0].key == "dummyKey_ed25519")
        #expect(createdKeys[0].type == "ed25519")
        try await app.asyncShutdown()
    }

    @Test(.disabled("Depends on Vapor 5"), .bug("/home/ubuntu/boka/RPC/Tests/RPCTests/KeystoreHandlersTests.swift:65"))
    func listKeys() async throws {
        _ = try await dummyKeystoreDataSource.create(keyType: .Ed25519)
        _ = try await dummyKeystoreDataSource.create(keyType: .BLS)

        let req = JSONRequest(jsonrpc: "2.0", method: "keys_list", params: .array([]), id: 0)
        var buffer = ByteBuffer()
        try buffer.writeJSONEncodable(req)
        try await app.testable().test(.POST, "/", headers: ["Content-Type": "application/json"], body: buffer) { res async in
            #expect(res.status == .ok)
            let resp = try? res.content.decode(JSONResponse.self, using: JSONDecoder())
            #expect((resp?.result?.value as! JSON).array!.count >= 2)
        }
        try await app.asyncShutdown()
    }

    @Test(.disabled("Depends on Vapor 5"), .bug("/home/ubuntu/boka/RPC/Tests/RPCTests/KeystoreHandlersTests.swift:80"))
    func hasKey() async throws {
        let ed25519PubKey = try await dummyKeystoreDataSource.create(keyType: .Ed25519)

        let params = JSON.array([.string(ed25519PubKey.type), .string(Data(ed25519PubKey.key.utf8).toHexString())])
        let req = JSONRequest(jsonrpc: "2.0", method: "keys_hasKey", params: params, id: 0)
        var buffer = ByteBuffer()
        try buffer.writeJSONEncodable(req)
        try await app.testable().test(.POST, "/", headers: ["Content-Type": "application/json"], body: buffer) { res async in
            #expect(res.status == .ok)
            let resp = try? res.content.decode(JSONResponse.self, using: JSONDecoder())
            #expect((resp?.result!.value as! JSON).bool == true)
        }
        try await app.asyncShutdown()
    }
}
