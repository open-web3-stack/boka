import Foundation
import Utils
import Vapor

protocol RPCHandler: Sendable {
    associatedtype Request: FromJSON
    associatedtype Response: Encodable

    var method: String { get }

    func handle(request: Request) async throws -> Response?
    func handle(jsonRequest: JSONRequest) async throws -> JSONResponse
}

extension RPCHandler {
    public func handle(jsonRequest: JSONRequest) async throws -> JSONResponse {
        let req = try Request(from: jsonRequest.params)
        let res = try await handle(request: req)
        return JSONResponse(
            id: jsonRequest.id,
            result: res
        )
    }
}
