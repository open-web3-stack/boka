import Blockchain
@testable import RPC
import Testing
import TracingUtils
@testable import Utils
import Vapor
import XCTVapor

public final class DummyNodeDataSource: Sendable {
    public let chainDataProvider: BlockchainDataProvider
    public init(
        chainDataProvider: BlockchainDataProvider
    ) {
        self.chainDataProvider = chainDataProvider
    }
}

extension DummyNodeDataSource: ChainDataSource {
    public func getFinalizedHead() async throws -> Data32? {
        try await chainDataProvider.getFinalizedHead()
    }

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
    var dataProvider: BlockchainDataProvider!

    func setUp() async throws {
        app = try await Application.make(.testing)
        let (genesisState, genesisBlock) = try! State.devGenesis(config: .minimal)
        dataProvider = try! await BlockchainDataProvider(InMemoryDataProvider(genesisState: genesisState, genesisBlock: genesisBlock))
        let rpcController = JSONRPCController(handlers: ChainHandlers
            .getHandlers(source: DummyNodeDataSource(chainDataProvider: dataProvider)))
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
