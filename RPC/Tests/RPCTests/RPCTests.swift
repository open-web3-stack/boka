@testable import RPC
import Vapor
import XCTest
import XCTVapor

final class RPCTests: XCTestCase {
    func testHTTPRPC() throws {
        let app = Application(.testing)
        defer { app.shutdown() }
        try configure(app)

        let rpcRequest = RPCRequest(jsonrpc: "2.0", method: "chain_getBlock", params: nil, id: 1)

        try app.test(.POST, "rpc", beforeRequest: { req in
            try req.content.encode(rpcRequest)
        }, afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
            let rpcResponse = try res.content.decode(RPCResponse.self)
            XCTAssertEqual(rpcResponse.jsonrpc, "2.0")
            XCTAssertEqual(rpcResponse.result, AnyCodable("example result"))
            XCTAssertNil(rpcResponse.error)
            XCTAssertEqual(rpcResponse.id, 1)
        })
    }

    func testWebSocketRPC() throws {
        let app = Application(.testing)
        defer { app.shutdown() }
        try configure(app)

        let promise = app.eventLoopGroup.next().makePromise(of: Void.self)

        try app.testable().webSocket("ws") { ws in
            let rpcRequest = RPCRequest(jsonrpc: "2.0", method: "chain_getBlock", params: nil, id: 1)
            let requestData = try JSONEncoder().encode(rpcRequest)

            ws.send(String(decoding: requestData, as: UTF8.self))

            ws.onText { _, text in
                let rpcResponse = try JSONDecoder().decode(RPCResponse.self, from: Data(text.utf8))
                XCTAssertEqual(rpcResponse.jsonrpc, "2.0")
                XCTAssertEqual(rpcResponse.result, AnyCodable("example result"))
                XCTAssertNil(rpcResponse.error)
                XCTAssertEqual(rpcResponse.id, 1)
                promise.succeed(())
            }
        }

        try promise.futureResult.wait()
    }
}
