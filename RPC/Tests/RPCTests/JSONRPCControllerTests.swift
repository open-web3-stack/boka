import Blockchain
@testable import RPC
import Testing
import TracingUtils
import Vapor
import XCTVapor

struct DummySource: SystemDataSource {}

final class JSONRPCControllerTests {
    var app: Application

    init() throws {
        app = Application(.testing)

        let rpcController = JSONRPCController(handlers: SystemHandlers.getHandlers(source: DummySource()))
        try app.register(collection: rpcController)
    }

    deinit {
        app.shutdown()
    }

    @Test func health() throws {
        let req = JSONRequest(jsonrpc: "2.0", method: "system_health", params: nil, id: 1)
        var buffer = ByteBuffer()
        try buffer.writeJSONEncodable(req)
        try app.test(.POST, "/", headers: ["Content-Type": "application/json"], body: buffer) { res in
            #expect(res.status == .ok)
            let resp = try res.content.decode(JSONResponse.self, using: JSONDecoder())
            #expect(resp.result?.value != nil)
        }
    }
}
