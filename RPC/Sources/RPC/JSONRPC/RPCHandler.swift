import Foundation
import Vapor

protocol RPCHandler {
    associatedtype Request: Content
    associatedtype Response: Content

    var method: String { get }

    func handle(request: JSONRequest<Request>) async throws -> Response
}

enum VoidRequest: Content, Codable {
    case void

    init(from _: Decoder) throws {
        // read nothing
        self = .void
    }

    func encode(to _: Encoder) throws {
        // write nothing
    }
}
