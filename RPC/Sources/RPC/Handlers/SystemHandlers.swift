import Utils

enum SystemHandlers {
    static let handlers: [any RPCHandler.Type] = [
        Health.self,
        Version.self,
    ]

    static func getHandlers(source _: SystemDataSource) -> [any RPCHandler] {
        [
            Health(),
            Version(),
        ]
    }

    struct Health: RPCHandler {
        typealias Request = VoidRequest
        typealias Response = Bool

        static var method: String { "system_health" }

        func handle(request _: Request) async throws -> Response? {
            true
        }
    }

    struct Version: RPCHandler {
        typealias Request = VoidRequest
        typealias Response = String

        static var method: String { "system_version" }

        func handle(request _: Request) async throws -> Response? {
            "0.0.1"
        }
    }
}
