import Utils
import Vapor

struct JSONRequest: Content {
    let jsonrpc: String
    let method: String
    let params: JSON?
    let id: JSON
}

struct JSONResponse: Content {
    let jsonrpc: String
    let result: AnyCodable?
    let error: JSONError?
    let id: JSON?

    init(id: JSON?, result: (any Encodable)?) {
        jsonrpc = "2.0"
        self.result = result.map(AnyCodable.init)
        error = nil
        self.id = id
    }

    init(id: JSON?, error: JSONError) {
        jsonrpc = "2.0"
        result = nil
        self.error = error
        self.id = id
    }
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
