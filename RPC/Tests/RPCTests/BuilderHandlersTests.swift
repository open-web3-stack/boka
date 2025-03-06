import Blockchain
@testable import RPC
import Testing
import TracingUtils
@testable import Utils
import Vapor
import XCTVapor

public final class DummyBuildDataSource: Sendable {
    public let chainDataProvider: BlockchainDataProvider
    public init(
        chainDataProvider: BlockchainDataProvider
    ) {
        self.chainDataProvider = chainDataProvider
    }
}

extension DummyBuildDataSource: BuilderDataSource {
    public func submitWorkPackage(data _: Data) async throws -> Bool {
        true
    }
}

final class BuilderRPCControllerTests {
    var app: Application!
    var dataProvider: BlockchainDataProvider!

    func setUp() async throws {
        app = try await Application.make(.testing)
        let (genesisState, genesisBlock) = try! State.devGenesis(config: .minimal)
        dataProvider = try! await BlockchainDataProvider(InMemoryDataProvider(genesisState: genesisState, genesisBlock: genesisBlock))
        let rpcController = JSONRPCController(handlers: BuilderHandlers
            .getHandlers(source: DummyBuildDataSource(chainDataProvider: dataProvider)))
        try app.register(collection: rpcController)
    }

    @Test func submitWorkPackage() async throws {
        try await setUp()
        let hashHex = await dataProvider.bestHead.hash.toHexString()
        let params = JSON.array([.string(hashHex)])
        let req = JSONRequest(jsonrpc: "2.0", method: "builder_submitWorkPackage", params: params, id: 0)
        var buffer = ByteBuffer()
        try buffer.writeJSONEncodable(req)
        try await app.test(.POST, "/", headers: ["Content-Type": "application/json"], body: buffer) { res async in
            #expect(res.status == .ok)
            let resp = try! res.content.decode(JSONResponse.self, using: JSONDecoder())
            #expect((resp.result!.value as! Utils.JSON).bool == true)
        }
        try await app.asyncShutdown()
    }
}
