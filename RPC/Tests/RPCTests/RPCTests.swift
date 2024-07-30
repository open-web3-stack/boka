@testable import RPC
import Vapor
import XCTest

final class RPCControllerTests: XCTestCase {
    var app: Application!

    override func setUp() {
        super.setUp()
        app = Application(.testing)

        let rpcController = RPCController()
        try app.register(collection: rpcController)
    }

    override func tearDown() {
        app.shutdown()
        super.tearDown()
    }

    func testRPCRequest() throws {
        let request = RPCRequest<AnyContent>(jsonrpc: "2.0", method: "chain_getBlock", params: BlockParams(blockHash: "dummyHash"), id: 1)
        let requestData = try JSONEncoder().encode(request)

        try app.test(.POST, "rpc", headers: ["Content-Type": "application/json"], body: ByteBuffer(data: requestData)) { res in
            XCTAssertEqual(res.status, .ok)
            let rpcResponse = try res.content.decode(RPCResponse<AnyContent>.self)
            XCTAssertEqual(rpcResponse.jsonrpc, "2.0")
            XCTAssertEqual(rpcResponse.id, 1)
        }
    }

    func testInvalidRPCRequest() throws {
        let invalidJSON = """
        {
            "jsonrpc": "2.0",
            "method": "unknown_method",
            "id": 1
        }
        """
        let requestData = invalidJSON.data(using: .utf8)!

        try app.test(.POST, "rpc", headers: ["Content-Type": "application/json"], body: ByteBuffer(data: requestData)) { res in
            XCTAssertEqual(res.status, .badRequest)
            let rpcResponse = try res.content.decode(RPCResponse<RPCError>.self)
            XCTAssertEqual(rpcResponse.jsonrpc, "2.0")
            XCTAssertEqual(rpcResponse.error?.code, -32601) // Method not found
        }
    }

    func testWebSocketRPCRequest() throws {
        let request = RPCRequest<AnyContent>(jsonrpc: "2.0", method: "chain_getHeader", params: HeaderParams(blockHash: "dummyHash"), id: 1)
        let requestData = try JSONEncoder().encode(request)
        let requestString = String(decoding: responseData, as: UTF8.self)

        try app.testable().ws("ws") { ws in
            ws.send(requestString)
            ws.onText { _, text in
                let rpcResponse = try JSONDecoder().decode(RPCResponse<AnyContent>.self, from: Data(text.utf8))
                XCTAssertEqual(rpcResponse.jsonrpc, "2.0")
                XCTAssertEqual(rpcResponse.id, 1)
            }
        }
    }
}
