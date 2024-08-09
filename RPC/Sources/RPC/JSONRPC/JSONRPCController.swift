import Blockchain
import TracingUtils
import Utils
import Vapor

let logger = Logger(label: "RPC.RPCController")

typealias JSONRPCHandler = @Sendable (JSONRequest) async throws -> any Encodable

final class JSONRPCController: RouteCollection, Sendable {
    let handlers: [String: JSONRPCHandler]
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    init(handlers: [String: JSONRPCHandler]) {
        self.handlers = handlers
    }

    func boot(routes: RoutesBuilder) throws {
        // HTTP JSON-RPC route
        routes.post("", use: handleRPCRequest)

        // WebSocket JSON-RPC route
        routes.webSocket("", onUpgrade: handleWebSocket)
    }

    func handleRPCRequest(_ req: Request) async throws -> Response {
        let jsonRequest = try req.content.decode(JSONRequest.self)
        let jsonResponse = await handleRequest(jsonRequest)
        return try Response(status: .ok, body: .init(data: encoder.encode(jsonResponse)))
    }

    func handleWebSocket(req _: Request, ws: WebSocket) {
        ws.onText { ws, text in
            Task {
                await self.processWebSocketRequest(ws, text: text)
            }
        }

        ws.onBinary { ws, _ in
            logger.debug("Received binary data on WebSocket. Closing connection.")
            try? await ws.close()
        }
    }

    private func processWebSocketRequest(_ ws: WebSocket, text: String) async {
        do {
            let jsonRequest = try decoder.decode(JSONRequest.self, from: Data(text.utf8))
            let jsonResponse = await handleRequest(jsonRequest)
            let responseData = try encoder.encode(jsonResponse)
            try await ws.send(raw: responseData, opcode: .text)
        } catch {
            logger.debug("Failed to decode JSON request: \(error)")

            let rpcError = JSONError(code: -32600, message: "Invalid Request")
            let rpcResponse = JSONResponse(jsonrpc: "2.0", result: nil, error: rpcError, id: nil)

            do {
                let responseData = try encoder.encode(rpcResponse)
                try await ws.send(raw: responseData, opcode: .text)
            } catch {
                logger.error("Failed to send WebSocket error response: \(error)")
                try? await ws.close()
            }
        }
    }

    func handleRequest(_ request: JSONRequest) async -> JSONResponse {
        do {
            let method = request.method
            guard let handler = handlers[method] else {
                return JSONResponse(jsonrpc: "2.0", result: nil, error: JSONError.methodNotFound(method), id: request.id)
            }

            let res = try await handler(request)
            return JSONResponse(jsonrpc: "2.0", result: AnyCodable(res), error: nil, id: request.id)
        } catch {
            logger.error("Failed to handle JSON request: \(error)")

            let rpcError = JSONError(code: -32600, message: "Invalid Request")
            return JSONResponse(jsonrpc: "2.0", result: nil, error: rpcError, id: request.id)
        }
    }
}
