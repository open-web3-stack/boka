import Blockchain
import Codec
@testable import RPC
import Testing
import TracingUtils
import Utils
import Vapor
import XCTVapor

actor DummyKeystoreDataSource {
    var keys: [String] = []
    func addKey(_ key: String) {
        keys.append(key)
    }
}

extension DummyKeystoreDataSource: KeystoreDataSource {
    public func createKey(keyType: CreateKeyType) async throws -> String {
        let publicKey = "\(keyType.rawValue)_PublicKey_\(UUID().uuidString)"
        keys.append(publicKey)
        return publicKey
    }

    public func listKeys() async throws -> [String] {
        keys
    }

    public func hasKey(publicKey: Data) async throws -> Bool {
        keys.contains(publicKey.toHexString())
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
        let params = JSON.array([.init(integerLiteral: keyType)])

        let req = JSONRequest(jsonrpc: "2.0", method: "keys_create", params: params, id: 0)
        var buffer = ByteBuffer()
        try buffer.writeJSONEncodable(req)
        try await app.test(.POST, "/", headers: ["Content-Type": "application/json"], body: buffer) { res async in
            #expect(res.status == .ok)
            let resp = try? res.content.decode(JSONResponse.self, using: JSONDecoder())
            #expect(resp?.result?.value != nil)
            if let publicKey = resp?.result?.value as? String {
                let keys = await self.dummyKeystoreDataSource.keys
                #expect(keys.contains(publicKey))
            }
        }

        let keys = await dummyKeystoreDataSource.keys
        #expect(keys.count == 1)
        try await app.asyncShutdown()
    }

    @Test
    func listKeys() async throws {
        await dummyKeystoreDataSource.addKey("BLS_PublicKey_1")
        await dummyKeystoreDataSource.addKey("Ed25519_PublicKey_2")

        let req = JSONRequest(jsonrpc: "2.0", method: "keys_list", params: JSON.array([]), id: 0)
        var buffer = ByteBuffer()
        try buffer.writeJSONEncodable(req)
        try await app.test(.POST, "/", headers: ["Content-Type": "application/json"], body: buffer) { res async in
            #expect(res.status == .ok)
            let resp = try? res.content.decode(JSONResponse.self, using: JSONDecoder())
            if let keys = resp?.result?.value as? [String] {
                #expect(keys.count == 2)
                #expect(keys.contains("BLS_PublicKey_1"))
                #expect(keys.contains("Ed25519_PublicKey_2"))
            }
        }
        try await app.asyncShutdown()
    }

    @Test
    func hasKey() async throws {
        let publicKey = "BLS_PublicKey_1"
        let publicKeyString = Data(publicKey.utf8).toHexString()

        await dummyKeystoreDataSource.addKey(publicKeyString)

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
