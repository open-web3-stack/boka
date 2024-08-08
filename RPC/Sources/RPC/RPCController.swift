import Blockchain
import Utils
import Vapor

final class RPCController: RouteCollection, Sendable {
    let source: DataSource

    init(source: DataSource) {
        self.source = source
    }

    func boot(routes: RoutesBuilder) throws {
        // HTTP JSON-RPC route
        routes.post("", use: handleRPCRequest)

        // WebSocket JSON-RPC route
        routes.webSocket("", onUpgrade: handleWebSocket)
    }

    func handleRPCRequest(_ req: Request) async throws -> Response {
        do {
            let rpcRequest = try req.content.decode(RPCRequest<AnyContent>.self)
            // Handle the JSON-RPC request
            let result = try await handleMethod(rpcRequest.method, params: rpcRequest.params)
            let rpcResponse = RPCResponse(jsonrpc: "2.0", result: AnyContent(result ?? ""), error: nil, id: rpcRequest.id)
            return try Response(status: .ok, body: .init(data: JSONEncoder().encode(rpcResponse)))
        } catch {
            let rpcError = RPCError(code: -32600, message: "Invalid Request")
            let rpcResponse = RPCResponse<RPCError>(jsonrpc: "2.0", result: nil, error: rpcError, id: nil)

            do {
                let responseData = try JSONEncoder().encode(rpcResponse)
                return Response(status: .badRequest, body: .init(data: responseData))
            } catch {
                print("Failed to encode error response: \(error)")
                return Response(status: .badRequest, body: .init(data: Data()))
            }
        }
    }

    func handleWebSocket(req _: Request, ws: WebSocket) {
        ws.onText { ws, text in
            Task {
                await self.processWebSocketRequest(ws, text: text)
            }
        }
    }

    private func processWebSocketRequest(_ ws: WebSocket, text: String) async {
        do {
            let rpcRequest = try JSONDecoder().decode(RPCRequest<AnyContent>.self, from: Data(text.utf8))
            let result = try await handleMethod(rpcRequest.method, params: rpcRequest.params?.value)
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

    func handleChainGetBlock(params: BlockParams?) async throws -> CodableBlock? {
        // Fetch the block by hash or number
        if let hash = params?.blockHash {
            guard let data = Data(fromHexString: hash), let data32 = Data32(data) else {
                throw RPCError(code: -32602, message: "Invalid block hash")
            }
            let block = try await source.getBlock(hash: data32)
            return block.map { CodableBlock(from: $0) }
        } else {
            let block = try await source.getBestBlock()
            return CodableBlock(from: block)
        }
    }

    func handleChainGetHeader(params _: HeaderParams?) async throws -> CodableHeader? {
        // Fetch the header by hash or number
        nil
    }

    func handleMethod(_ method: String, params: Any?) async throws -> Any? {
        switch method {
        case "health":
            return true
        case "chain_getBlock":
            return try await handleChainGetBlock(params: params as? BlockParams)
        case "chain_getHeader":
            return try await handleChainGetHeader(params: params as? HeaderParams)
        default:
            throw RPCError(code: -32601, message: "Method not found")
        }
    }
}
