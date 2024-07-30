import Blockchain
import Vapor

final class RPCController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        // HTTP JSON-RPC route
        routes.post("rpc", use: handleRPCRequest)

        // WebSocket JSON-RPC route
        routes.webSocket("ws", onUpgrade: handleWebSocket)
    }

    func handleRPCRequest(_ req: Request) -> EventLoopFuture<Response> {
        do {
            let rpcRequest = try req.content.decode(RPCRequest<AnyContent>.self)
            // Handle the JSON-RPC request
            let result = try RPCController.handleMethod(rpcRequest.method, params: rpcRequest.params)
            let rpcResponse = RPCResponse(jsonrpc: "2.0", result: AnyContent(result ?? ""), error: nil, id: rpcRequest.id)
            return try req.eventLoop.makeSucceededFuture(Response(status: .ok, body: .init(data: JSONEncoder().encode(rpcResponse))))
        } catch {
            let rpcError = RPCError(code: -32600, message: "Invalid Request")
            let rpcResponse = RPCResponse<RPCError>(jsonrpc: "2.0", result: nil, error: rpcError, id: nil)

            do {
                let responseData = try JSONEncoder().encode(rpcResponse)
                return req.eventLoop.makeSucceededFuture(Response(status: .badRequest, body: .init(data: responseData)))
            } catch {
                print("Failed to encode error response: \(error)")
                return req.eventLoop.makeSucceededFuture(Response(status: .badRequest, body: .init(data: Data())))
            }
        }
    }

    func handleWebSocket(req _: Request, ws: WebSocket) {
        ws.onText { ws, text in
            Task {
                await RPCController.processWebSocketRequest(ws, text: text)
            }
        }
    }

    private static func processWebSocketRequest(_ ws: WebSocket, text: String) async {
        do {
            let rpcRequest = try JSONDecoder().decode(RPCRequest<AnyContent>.self, from: Data(text.utf8))
            let result = try handleMethod(rpcRequest.method, params: rpcRequest.params?.value)
            let rpcResponse = RPCResponse(jsonrpc: "2.0", result: AnyContent(result ?? ""), error: nil, id: rpcRequest.id)
            let responseData = try JSONEncoder().encode(rpcResponse)
            try await ws.send(String(decoding: responseData, as: UTF8.self))
        } catch {
            let rpcError = RPCError(code: -32600, message: "Invalid Request")
            let rpcResponse = RPCResponse<RPCError>(jsonrpc: "2.0", result: nil, error: rpcError, id: nil)

            do {
                let responseData = try JSONEncoder().encode(rpcResponse)
                try await ws.send(String(decoding: responseData, as: UTF8.self))
            } catch {
                print("Failed to send WebSocket error response: \(error)")
            }
        }
    }

    static func handleChainGetBlock(params _: BlockParams?) -> CodableBlock? {
        // Fetch the block by hash or number
        nil
    }

    static func handleChainGetHeader(params _: HeaderParams?) -> CodableHeader? {
        // Fetch the header by hash or number
        nil
    }

    static func handleMethod(_ method: String, params: Any?) throws -> Any? {
        switch method {
        case "chain_getBlock":
            return handleChainGetBlock(params: params as? BlockParams)
        case "chain_getHeader":
            return handleChainGetHeader(params: params as? HeaderParams)
        default:
            throw RPCError(code: -32601, message: "Method not found")
        }
    }
}
