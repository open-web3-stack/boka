import Utils
import Vapor

public struct JSONRequest: Content {
    public let jsonrpc: String
    public let method: String
    public let params: JSON?
    public let id: JSON
}

public struct JSONResponse: Content {
    public let jsonrpc: String
    public let result: AnyCodable?
    public let error: JSONError?
    public let id: JSON?

    public init(id: JSON?, result: (any Encodable)?) {
        jsonrpc = "2.0"
        self.result = result.map(AnyCodable.init)
        error = nil
        self.id = id
    }

    public init(id: JSON?, error: JSONError) {
        jsonrpc = "2.0"
        result = nil
        self.error = error
        self.id = id
    }
}

public struct JSONError: Content, Error {
    let code: Int
    let message: String
}

extension JSONError {
    public static func methodNotFound(_ method: String) -> JSONError {
        JSONError(code: -32601, message: "Method not found: \(method)")
    }
}
