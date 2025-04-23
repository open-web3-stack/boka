import Blockchain
import Testing
import TracingUtils
import Vapor
import XCTVapor

@testable import RPC
@testable import Utils

final class StateHandlersTests {
    var app: Application!
    var dataProvider: BlockchainDataProvider!

    func setUp() async throws {
        app = try await Application.make(.testing)
        let (genesisState, genesisBlock) = try! State.devGenesis(config: .minimal)
        dataProvider = try! await BlockchainDataProvider(InMemoryDataProvider(genesisState: genesisState, genesisBlock: genesisBlock))
        let rpcController = JSONRPCController(handlers: StateHandlers
            .getHandlers(source: DummyNodeDataSource(chainDataProvider: dataProvider)))
        try app.register(collection: rpcController)
    }

    @Test func getKeys() async throws {
        try await setUp()
        let hashHex = await dataProvider.bestHead.hash.toHexString()
        let params = JSON.array(
            [
                .string(hashHex),
                .init(integerLiteral: 10),
                .null,
                .null,
            ]
        )
        let req = JSONRequest(jsonrpc: "2.0", method: "state_getKeys", params: params, id: 1)
        var buffer = ByteBuffer()
        try buffer.writeJSONEncodable(req)
        try await app.testable().test(.POST, "/", headers: ["Content-Type": "application/json"], body: buffer) { res async in
            #expect(res.status == .ok)
            let resp = try! res.content.decode(JSONResponse.self, using: JSONDecoder())
            #expect(resp.result?.value != nil)
        }
        try await app.asyncShutdown()
    }

    @Test func getStorage() async throws {
        try await setUp()
        let hashHex = await dataProvider.bestHead.hash.toHexString()
        let params = JSON.array([.string(hashHex)])
        let req = JSONRequest(jsonrpc: "2.0", method: "state_getStorage", params: params, id: 2)
        var buffer = ByteBuffer()
        try buffer.writeJSONEncodable(req)
        try await app.testable().test(.POST, "/", headers: ["Content-Type": "application/json"], body: buffer) { res async in
            #expect(res.status == .ok)
            let resp = try! res.content.decode(JSONResponse.self, using: JSONDecoder())
            #expect(resp.result?.value != nil)
        }
        try await app.asyncShutdown()
    }
}
