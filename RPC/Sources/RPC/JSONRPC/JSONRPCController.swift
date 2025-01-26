import Blockchain
import TracingUtils
import Utils
import Vapor

let logger = Logger(label: "RPC.RPCController")

final class JSONRPCController: RouteCollection, Sendable {
    let handlers: [String: any RPCHandler]
    let encoder: JSONEncoder
    let decoder: JSONDecoder

    init(handlers: [any RPCHandler]) {
        var dict = [String: any RPCHandler]()
        for handler in handlers {
            let method = type(of: handler).method
            if dict.keys.contains(method) {
                logger.warning("Duplicated handler: \(method)")
            }
            dict[method] = handler
        }
        self.handlers = dict

        encoder = JSONEncoder()
        encoder.dataEncodingStrategy = .hex
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]

        decoder = JSONDecoder()
        decoder.dataDecodingStrategy = .hex
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
            let rpcResponse = JSONResponse(id: nil, error: rpcError)

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
                return JSONResponse(id: request.id, error: JSONError.methodNotFound(method))
            }

            return try await handler.handle(jsonRequest: request)
        } catch {
            logger.error("Failed to handle JSON request: \(error)")

            let rpcError = JSONError(code: -32600, message: "Invalid Request")
            return JSONResponse(id: request.id, error: rpcError)
        }
    }
}
