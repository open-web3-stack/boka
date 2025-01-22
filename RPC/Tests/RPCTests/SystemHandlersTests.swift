import Blockchain
import Testing
import TracingUtils
import Vapor
import XCTVapor

@testable import RPC
@testable import Utils

struct DummySource: SystemDataSource {}

final class SystemHandlersTests {
    var app: Application

    init() throws {
        app = Application(.testing)

        let rpcController = JSONRPCController(
            handlers: SystemHandlers.getHandlers(source: DummySource())
        )
        try app.register(collection: rpcController)
    }

    deinit {
        app.shutdown()
    }

    @Test func health() throws {
        let req = JSONRequest(jsonrpc: "2.0", method: "system_health", params: nil, id: 1)
        var buffer = ByteBuffer()
        try buffer.writeJSONEncodable(req)
        try app.test(.POST, "/", headers: ["Content-Type": "application/json"], body: buffer) {
            res in
            #expect(res.status == .ok)
            let resp = try res.content.decode(JSONResponse.self, using: JSONDecoder())
            #expect((resp.result!.value as! Utils.JSON).bool == true)
        }
    }

    @Test func implementation() throws {
        let req = JSONRequest(jsonrpc: "2.0", method: "system_implementation", params: nil, id: 2)
        var buffer = ByteBuffer()
        try buffer.writeJSONEncodable(req)
        try app.test(.POST, "/", headers: ["Content-Type": "application/json"], body: buffer) {
            res in
            #expect(res.status == .ok)
            let resp = try res.content.decode(JSONResponse.self, using: JSONDecoder())
            #expect((resp.result!.value as! Utils.JSON).string == "Boka")
        }
    }

    @Test func version() throws {
        let req = JSONRequest(jsonrpc: "2.0", method: "system_version", params: nil, id: 3)
        var buffer = ByteBuffer()
        try buffer.writeJSONEncodable(req)
        try app.test(.POST, "/", headers: ["Content-Type": "application/json"], body: buffer) {
            res in
            #expect(res.status == .ok)
            let resp = try res.content.decode(JSONResponse.self, using: JSONDecoder())
            #expect((resp.result!.value as! Utils.JSON).string == "0.0.1")
        }
    }

    @Test func properties() throws {
        let req = JSONRequest(jsonrpc: "2.0", method: "system_properties", params: nil, id: 4)
        var buffer = ByteBuffer()
        try buffer.writeJSONEncodable(req)
        try app.test(.POST, "/", headers: ["Content-Type": "application/json"], body: buffer) {
            res in
            #expect(res.status == .ok)
            let resp = try res.content.decode(JSONResponse.self, using: JSONDecoder())
            #expect(resp.result?.value != nil)
        }
    }

    @Test func nodeRoles() throws {
        let req = JSONRequest(jsonrpc: "2.0", method: "system_nodeRoles", params: nil, id: 5)
        var buffer = ByteBuffer()
        try buffer.writeJSONEncodable(req)
        try app.test(.POST, "/", headers: ["Content-Type": "application/json"], body: buffer) {
            res in
            #expect(res.status == .ok)
            let resp = try res.content.decode(JSONResponse.self, using: JSONDecoder())
            #expect((resp.result!.value as! Utils.JSON).array == [])
        }
    }

    @Test func chain() throws {
        let req = JSONRequest(jsonrpc: "2.0", method: "system_chain", params: nil, id: 6)
        var buffer = ByteBuffer()
        try buffer.writeJSONEncodable(req)
        try app.test(.POST, "/", headers: ["Content-Type": "application/json"], body: buffer) {
            res in
            #expect(res.status == .ok)
            let resp = try res.content.decode(JSONResponse.self, using: JSONDecoder())
            #expect((resp.result!.value as! Utils.JSON).string == "dev")
        }
    }
}
