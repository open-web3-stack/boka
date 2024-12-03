import Foundation
import Utils
import Vapor

public protocol RPCHandler: Sendable {
    associatedtype Request: RequestParameter
    associatedtype Response: Encodable

    static var method: String { get }

    func handle(request: Request) async throws -> Response?
    func handle(jsonRequest: JSONRequest) async throws -> JSONResponse

    // for OpenRPC spec generation
    static var summary: String? { get }

    static var requestType: any RequestParameter.Type { get }
    static var requestNames: [String] { get }
    static var responseType: any Encodable.Type { get }
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

    public static var requestType: any RequestParameter.Type {
        Request.self
    }

    public static var responseType: any Encodable.Type {
        Response.self
    }

    public static var requestNames: [String] {
        []
    }
}
