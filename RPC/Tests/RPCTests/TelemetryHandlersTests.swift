import Blockchain
import Testing
import TracingUtils
import Vapor
import XCTVapor

@testable import RPC
@testable import Utils

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
    var app: Application

    init() throws {
        app = Application(.testing)

        let rpcController = JSONRPCController(
            handlers: TelemetryHandlers.getHandlers(source: TelemetryDummySource())
        )
        try app.register(collection: rpcController)
    }

    deinit {
        app.shutdown()
    }

    @Test func name() throws {
        let req = JSONRequest(jsonrpc: "2.0", method: "telemetry_name", params: nil, id: 1)
        var buffer = ByteBuffer()
        try buffer.writeJSONEncodable(req)
        try app.testable().test(.POST, "/", headers: ["Content-Type": "application/json"], body: buffer) { res in
            #expect(res.status == .ok)
            let resp = try res.content.decode(JSONResponse.self, using: JSONDecoder())
            #expect((resp.result!.value as! Utils.JSON).string == "TestNode")
        }
    }

    @Test func peersCount() throws {
        let req = JSONRequest(jsonrpc: "2.0", method: "telemetry_peersCount", params: nil, id: 2)
        var buffer = ByteBuffer()
        try buffer.writeJSONEncodable(req)
        try app.testable().test(.POST, "/", headers: ["Content-Type": "application/json"], body: buffer) { res in
            #expect(res.status == .ok)
            let resp = try res.content.decode(JSONResponse.self, using: JSONDecoder())
            #expect((resp.result!.value as! Utils.JSON).number == 42)
        }
    }

    @Test func networkKey() throws {
        let req = JSONRequest(jsonrpc: "2.0", method: "telemetry_networkKey", params: nil, id: 3)
        var buffer = ByteBuffer()
        try buffer.writeJSONEncodable(req)
        try app.testable().test(.POST, "/", headers: ["Content-Type": "application/json"], body: buffer) { res in
            #expect(res.status == .ok)
            let resp = try res.content.decode(JSONResponse.self, using: JSONDecoder())
            #expect((resp.result!.value as! Utils.JSON).string == "Ed25519:TestKey")
        }
    }
}
