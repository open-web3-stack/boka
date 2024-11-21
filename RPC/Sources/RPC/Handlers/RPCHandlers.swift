import Utils

enum RPCHandlers {
    static func getHandlers(source: [any RPCHandler]) -> [any RPCHandler] {
        [
            Methods(source: source),
        ]
    }

    struct Methods: RPCHandler {
        var method: String { "rpc_methods" }
        typealias Request = VoidRequest
        typealias Response = [String]

        private let methods: [String]

        init(source: [any RPCHandler]) {
            methods = source.map(\.method)
        }

        func handle(request _: Request) async throws -> Response? {
            methods
        }
    }
}
