import Blockchain
@testable import RPC
import Testing
import TracingUtils
@testable import Utils
import Vapor
import XCTVapor

struct TelemetryDummySource: TelemetryDataSource {
    func name() async throws -> String {
        "TestNode"
    }

    func getPeersCount() async throws -> Int {
        42
    }

    func getNetworkKey() async throws -> String {
        "Ed25519:TestKey"
    }
}

final class TelemetryHandlersTests {
    var app: Application!

    func setUp() async throws {
        app = try await Application.make(.testing)
        let rpcController = JSONRPCController(
            handlers: TelemetryHandlers.getHandlers(source: TelemetryDummySource()),
        )
        try app.register(collection: rpcController)
    }

    @Test func name() async throws {
        try await setUp()
        let req = JSONRequest(jsonrpc: "2.0", method: "telemetry_name", params: nil, id: 1)
        var buffer = ByteBuffer()
        try buffer.writeJSONEncodable(req)
        try await app.testable().test(.POST, "/", headers: ["Content-Type": "application/json"], body: buffer) { res async in
            #expect(res.status == .ok)
            let resp = try! res.content.decode(JSONResponse.self, using: JSONDecoder())
            #expect((resp.result!.value as! Utils.JSON).string == "TestNode")
        }
        try await app.asyncShutdown()
    }

    @Test func peersCount() async throws {
        try await setUp()
        let req = JSONRequest(jsonrpc: "2.0", method: "telemetry_peersCount", params: nil, id: 2)
        var buffer = ByteBuffer()
        try buffer.writeJSONEncodable(req)
        try await app.testable().test(.POST, "/", headers: ["Content-Type": "application/json"], body: buffer) { res async in
            #expect(res.status == .ok)
            let resp = try! res.content.decode(JSONResponse.self, using: JSONDecoder())
            #expect((resp.result!.value as! Utils.JSON).number == 42)
        }
        try await app.asyncShutdown()
    }

    @Test func networkKey() async throws {
        try await setUp()
        let req = JSONRequest(jsonrpc: "2.0", method: "telemetry_networkKey", params: nil, id: 3)
        var buffer = ByteBuffer()
        try buffer.writeJSONEncodable(req)
        try await app.testable().test(.POST, "/", headers: ["Content-Type": "application/json"], body: buffer) { res async in
            #expect(res.status == .ok)
            let resp = try! res.content.decode(JSONResponse.self, using: JSONDecoder())
            #expect((resp.result!.value as! Utils.JSON).string == "Ed25519:TestKey")
        }
        try await app.asyncShutdown()
    }
}
