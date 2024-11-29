import Utils

public enum SystemHandlers {
    public static let handlers: [any RPCHandler.Type] = [
        Health.self,
        Version.self,
    ]

    public static func getHandlers(source _: SystemDataSource) -> [any RPCHandler] {
        [
            Health(),
            Version(),
        ]
    }

    public struct Health: RPCHandler {
        public typealias Request = VoidRequest
        public typealias Response = Bool

        public static var method: String { "system_health" }
        public static var summary: String? { "Returns true if the node is healthy." }

        public func handle(request _: Request) async throws -> Response? {
            true
        }
    }

    public struct Implementation: RPCHandler {
        public typealias Request = VoidRequest
        public typealias Response = String

        public static var method: String { "system_implementation" }
        public static var summary: String? { "Returns the implementation name of the node." }

        public func handle(request _: Request) async throws -> Response? {
            "Boka"
        }
    }

    public struct Version: RPCHandler {
        public typealias Request = VoidRequest
        public typealias Response = String

        public static var method: String { "system_version" }
        public static var summary: String? { "Returns the version of the node." }

        public func handle(request _: Request) async throws -> Response? {
            "0.0.1"
        }
    }
}
