import Blockchain
@testable import RPC
import Testing
import TracingUtils
@testable import Utils
import Vapor
import XCTVapor

public final class NodeDataSource: Sendable {
    public let chainDataProvider: BlockchainDataProvider
    public init(
        chainDataProvider: BlockchainDataProvider
    ) {
        self.chainDataProvider = chainDataProvider
    }
}

extension NodeDataSource: ChainDataSource {
    public func getBestBlock() async throws -> BlockRef {
        try await chainDataProvider.getBlock(hash: chainDataProvider.bestHead.hash)
    }

    public func getBlock(hash: Data32) async throws -> BlockRef? {
        try await chainDataProvider.getBlock(hash: hash)
    }

    public func getState(blockHash: Data32, key: Data32) async throws -> Data? {
        let state = try await chainDataProvider.getState(hash: blockHash)
        return try await state.value.read(key: key)
    }

    public func getBlockHash(byTimeslot timeslot: TimeslotIndex) async throws -> Set<Data32> {
        try await chainDataProvider.getBlockHash(byTimeslot: timeslot)
    }

    public func getHeader(hash: Data32) async throws -> HeaderRef? {
        try await chainDataProvider.getHeader(hash: hash)
    }
}

final class ChainRPCControllerTests {
    var app: Application!

    func setUp() async throws {
        app = try await Application.make(.testing)
        let (genesisState, genesisBlock) = try! State.devGenesis(config: .minimal)
        let dataProvider = try! await BlockchainDataProvider(InMemoryDataProvider(genesisState: genesisState, genesisBlock: genesisBlock))
        let rpcController = JSONRPCController(handlers: ChainHandlers.getHandlers(source: NodeDataSource(chainDataProvider: dataProvider)))
//        let rpcController = JSONRPCController(handlers: SystemHandlers.getHandlers(source: DummySource()))

        try app.register(collection: rpcController)
    }

//    @Test func health() async throws {
//        try await setUp()
//
//        let req = JSONRequest(jsonrpc: "2.0", method: "system_health", params: nil, id: 1)
//        var buffer = ByteBuffer()
//        try buffer.writeJSONEncodable(req)
//        try await app.test(.POST, "/", headers: ["Content-Type": "application/json"], body: buffer) { res async in
//            #expect(res.status == .ok)
//            print("resp \(res.body.string)")
//            let resp = try! res.content.decode(JSONResponse.self, using: JSONDecoder())
//            #expect((resp.result!.value as! Utils.JSON).bool == true)
//
//        }
//        try await app.asyncShutdown()
//
//    }

    @Test func getBlock() async throws {
        try await setUp()
        let req = JSONRequest(jsonrpc: "2.0", method: "chain_getBlock", params: nil, id: 1)
        var buffer = ByteBuffer()
        try buffer.writeJSONEncodable(req)
        try await app.test(.POST, "/", headers: ["Content-Type": "application/json"], body: buffer) { res async in
            #expect(res.status == .ok)
            print("resp \(res.body.string)")
        }
        try await app.asyncShutdown()
    }
//
//    @Test func getBlockHash() throws {
//        let req = JSONRequest(jsonrpc: "2.0", method: "chain_getBlockHash", params: nil, id: 2)
//        var buffer = ByteBuffer()
//        try buffer.writeJSONEncodable(req)
//        try app.test(.POST, "/", headers: ["Content-Type": "application/json"], body: buffer) { res in
//            #expect(res.status == .ok)
//            let resp = try res.content.decode(JSONResponse.self, using: JSONDecoder())
    ////            #expect((resp.result!.value as! Utils.JSON).data == "test_block_hash".data(using: .utf8))
//        }
//    }
//
//    @Test func getFinalizedHead() throws {
//        let req = JSONRequest(jsonrpc: "2.0", method: "chain_getFinalziedHead", params: nil, id: 3)
//        var buffer = ByteBuffer()
//        try buffer.writeJSONEncodable(req)
//        try app.test(.POST, "/", headers: ["Content-Type": "application/json"], body: buffer) { res in
//            #expect(res.status == .ok)
//            let resp = try res.content.decode(JSONResponse.self, using: JSONDecoder())
    ////            #expect((resp.result!.value as! Utils.JSON).data == "finalized_head_hash".data(using: .utf8))
//        }
//    }
//
//    @Test func getHeader() throws {
//        let req = JSONRequest(jsonrpc: "2.0", method: "chain_getHeader", params: nil, id: 4)
//        var buffer = ByteBuffer()
//        try buffer.writeJSONEncodable(req)
//        try app.test(.POST, "/", headers: ["Content-Type": "application/json"], body: buffer) { res in
//            #expect(res.status == .ok)
//            let resp = try res.content.decode(JSONResponse.self, using: JSONDecoder())
    ////            #expect((resp.result!.value as! Utils.JSON).data == "best_header_data".data(using: .utf8))
//        }
//    }
}
