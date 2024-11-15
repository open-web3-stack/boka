import Utils

enum SystemHandlers {
    static func getHandlers(source: SystemDataSource) -> [RPCHandler] {
        [
            Health(),
            Name(source: source),
        ]
    }

    struct Health: RPCHandler {
        static var method: String { "system_health" }
        typealias Request = VoidRequest
        typealias Response = Bool

        func handle(request _: Request) async throws -> Response {
            true
        }
    }

    struct Name: RPCHandler {
        static var method: String { "system_name" }
        typealias Request = VoidRequest
        typealias Response = String

        private let source: SystemDataSource

        init(source: SystemDataSource) {
            self.source = source
        }

        func handle(request _: Request) async throws -> Response {
            try await source.name()
        }
    }
}
