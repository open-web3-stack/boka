import Utils

enum SystemHandlers {
    static func getHandlers(source _: SystemDataSource) -> [any RPCHandler] {
        [
            Health(),
            Version(),
        ]
    }

    struct Health: RPCHandler {
        var method: String { "system_health" }
        typealias Request = VoidRequest
        typealias Response = Bool

        func handle(request _: Request) async throws -> Response? {
            true
        }
    }

    struct Version: RPCHandler {
        var method: String { "system_version" }
        typealias Request = VoidRequest
        typealias Response = String

        func handle(request _: Request) async throws -> Response? {
            "0.0.1"
        }
    }
}
