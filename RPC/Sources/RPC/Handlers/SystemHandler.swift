import Utils

struct SystemHandler {
    static func getHandlers() -> [String: JSONRPCHandler] {
        let handler = SystemHandler()

        return [
            "system_health": handler.health,
            "system_name": handler.name,
        ]
    }

    func health(request _: JSONRequest) async throws -> any Encodable {
        true
    }

    func name(request _: JSONRequest) async throws -> any Encodable {
        "Boka"
    }
}

enum SystemHandlers {
    struct Health: RPCHandler {
        static var method: String { "system_health" }
        typealias Request = JSON
        typealias Response = Bool

        func handle(request _: Request) async throws -> Response {
            true
        }
    }
}
