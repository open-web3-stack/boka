// NOTE: Tests disabled - depends on Vapor 5
// These tests require Vapor 5 which has incompatible trait system
// Issue: Traits [HTTPClient, Multipart, TLS, WebSockets, bcrypt] have been enabled
// on package 'vapor' (vapor) that declares no traits.

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
    public func submitWorkPackage(coreIndex: CoreIndex, workPackage: Data, extrinsics: [Data]) async throws {
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

    @Test(.disabled("Depends on Vapor 5"), .bug("/home/ubuntu/boka/RPC/Tests/RPCTests/BuilderHandlersTests.swift:35"))
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
