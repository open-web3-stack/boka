import Utils

public enum RPCHandlers {
    public static let handlers: [any RPCHandler.Type] = [
        Methods.self,
    ]

    public static func getHandlers(source: [any RPCHandler.Type]) -> [any RPCHandler] {
        [Methods(source: source)]
    }

    public struct Methods: RPCHandler {
        public typealias Request = VoidRequest
        public typealias Response = [String]
        public typealias DataSource = [any RPCHandler.Type]

        public static var method: String { "rpc_methods" }
        public static var summary: String? { "Returns a list of available RPC methods." }

        private let methods: [String]

        init(source: [any RPCHandler.Type]) {
            methods = source.map { h in h.method }
        }

        public func handle(request _: Request) async throws -> Response? {
            methods
        }
    }
}
