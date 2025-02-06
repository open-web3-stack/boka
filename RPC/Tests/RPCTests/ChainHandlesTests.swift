import Blockchain
@testable import Node
@testable import RPC
import Testing
import TracingUtils
@testable import Utils
import Vapor
import XCTVapor

final class ChainRPCControllerTests {
    var app: Application!
    var dataProvider: BlockchainDataProvider!

    func setUp() async throws {
        app = try await Application.make(.testing)
        let dummyNodeDataSource = DummyNodeDataSource(genesis: .minimal)
        dataProvider = dummyNodeDataSource.dataProvider
        let (genesisState, genesisBlock) = try! State.devGenesis(config: .minimal)
        let rpcController = JSONRPCController(handlers: ChainHandlers
            .getHandlers(source: dummyNodeDataSource))
        try app.register(collection: rpcController)
    }

    @Test func getBlock() async throws {
        try await setUp()
        let hashHex = await dataProvider.bestHead.hash.toHexString()
        let params = JSON.array([.string(hashHex)])
        let req = JSONRequest(jsonrpc: "2.0", method: "chain_getBlock", params: params, id: 1)
        var buffer = ByteBuffer()
        try buffer.writeJSONEncodable(req)
        try await app.test(.POST, "/", headers: ["Content-Type": "application/json"], body: buffer) { res async in
            #expect(res.status == .ok)
            let resp = try! res.content.decode(JSONResponse.self, using: JSONDecoder())
            #expect(resp.result!.value != nil)
        }
        try await app.asyncShutdown()
    }

    @Test func getBlockHash() async throws {
        try await setUp()
        let timeslot = await dataProvider.bestHead.timeslot
        let params = JSON.array([JSON(integerLiteral: Int32(timeslot))])
        let req = JSONRequest(jsonrpc: "2.0", method: "chain_getBlockHash", params: params, id: 2)
        var buffer = ByteBuffer()
        try buffer.writeJSONEncodable(req)
        try await app.test(.POST, "/", headers: ["Content-Type": "application/json"], body: buffer) { res async in
            #expect(res.status == .ok)
            let resp = try! res.content.decode(JSONResponse.self, using: JSONDecoder())
            #expect(resp.result!.value != nil)
        }
        try await app.asyncShutdown()
    }

    @Test func getFinalizedHead() async throws {
        try await setUp()
        let req = JSONRequest(jsonrpc: "2.0", method: "chain_getFinalizedHead", params: nil, id: 3)
        var buffer = ByteBuffer()
        try buffer.writeJSONEncodable(req)
        try await app.test(.POST, "/", headers: ["Content-Type": "application/json"], body: buffer) { res async in
            #expect(res.status == .ok)
            let resp = try! res.content.decode(JSONResponse.self, using: JSONDecoder())
            #expect(resp.result!.value != nil)
        }
        try await app.asyncShutdown()
    }

    @Test func getHeader() async throws {
        try await setUp()
        let hashHex = await dataProvider.bestHead.hash.toHexString()
        let params = JSON.array([.string(hashHex)])
        let req = JSONRequest(jsonrpc: "2.0", method: "chain_getHeader", params: params, id: 4)
        var buffer = ByteBuffer()
        try buffer.writeJSONEncodable(req)
        try await app.test(.POST, "/", headers: ["Content-Type": "application/json"], body: buffer) { res async in
            #expect(res.status == .ok)
            let resp = try! res.content.decode(JSONResponse.self, using: JSONDecoder())
            #expect(resp.result!.value != nil)
        }
        try await app.asyncShutdown()
    }
}
