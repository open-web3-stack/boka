import Utils
import Vapor

struct JSONRequest: Content {
    let jsonrpc: String
    let method: String
    let params: JSON?
    let id: Int
}

struct JSONResponse: Content {
    let jsonrpc: String
    let result: AnyCodable?
    let error: JSONError?
    let id: Int?
}

struct JSONError: Content, Error {
    let code: Int
    let message: String
}

extension JSONError {
    static func methodNotFound(_ method: String) -> JSONError {
        JSONError(code: -32601, message: "Method not found: \(method)")
    }
}
