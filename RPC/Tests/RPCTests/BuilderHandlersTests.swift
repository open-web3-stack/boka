import Blockchain
import Codec
@testable import RPC
import Testing
import TracingUtils
import Utils
import Vapor
import XCTVapor

actor DummyBuildDataSource {
    var workPackageCalls: [(CoreIndex, Data, [Data])] = []
}

extension DummyBuildDataSource: BuilderDataSource {
    func submitWorkPackage(coreIndex: CoreIndex, workPackage: Data, extrinsics: [Data]) async throws {
        workPackageCalls.append((coreIndex, workPackage, extrinsics))
    }
}

final class BuilderRPCControllerTests {
    let app: Application
    let dummyBuildDataSource = DummyBuildDataSource()

    init() async throws {
        app = try await Application.make(.testing)
        let rpcController = JSONRPCController(handlers: BuilderHandlers.getHandlers(source: dummyBuildDataSource))
        try app.register(collection: rpcController)
    }

    @Test
    func submitWorkPackage() async throws {
        let workPackage = WorkPackage.dummy(config: .minimal)
        let encoded = try JamEncoder.encode(workPackage)
        let params = JSON.array([.number(1), .string("0x\(encoded.toHexString())"), .array([.string("0x010203"), .string("0x040506")])])

        let req = JSONRequest(jsonrpc: "2.0", method: "builder_submitWorkPackage", params: params, id: 0)
        var buffer = ByteBuffer()
        try buffer.writeJSONEncodable(req)
        try await app.testable().test(.POST, "/", headers: ["Content-Type": "application/json"], body: buffer) { res async in
            #expect(res.status == .ok)
            let resp = try? res.content.decode(JSONResponse.self, using: JSONDecoder())
            #expect(resp?.result?.value as? JSON == .boolean(true))
        }
        let calls = await dummyBuildDataSource.workPackageCalls
        #expect(calls.count == 1)
        #expect(calls[0].0 == 1)
        #expect(calls[0].1 == encoded)
        #expect(calls[0].2 == [Data([1, 2, 3]), Data([4, 5, 6])])
        try await app.asyncShutdown()
    }
}
