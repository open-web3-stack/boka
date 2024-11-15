import Foundation
import Vapor

protocol RPCHandler {
    static var method: String { get }
    associatedtype Request: Content
    associatedtype Response: Content

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
