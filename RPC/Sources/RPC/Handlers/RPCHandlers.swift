import Utils

enum RPCHandlers {
    static let handlers: [any RPCHandler.Type] = [
        Methods.self,
    ]

    static func getHandlers(source: [any RPCHandler.Type]) -> [any RPCHandler] {
        [Methods(source: source)]
    }

    struct Methods: RPCHandler {
        typealias Request = VoidRequest
        typealias Response = [String]
        typealias DataSource = [any RPCHandler.Type]

        static var method: String { "rpc_methods" }

        private let methods: [String]

        init(source: [any RPCHandler.Type]) {
            methods = source.map { h in h.method }
        }

        func handle(request _: Request) async throws -> Response? {
            methods
        }
    }
}
