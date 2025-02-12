import Utils

public enum SystemHandlers {
    public static let handlers: [any RPCHandler.Type] = [
        Health.self,
        Implementation.self,
        Version.self,
        Properties.self,
        NodeRoles.self,
        Chain.self,
    ]

    public static func getHandlers(source: SystemDataSource) -> [any RPCHandler] {
        [
            Health(source: source),
            Implementation(source: source),
            Version(source: source),
            Properties(source: source),
            NodeRoles(source: source),
            Chain(source: source),
        ]
    }

    struct Health: RPCHandler {
        public typealias Request = VoidRequest
        public typealias Response = Bool

        public static var method: String { "system_health" }
        public static var summary: String? { "Returns true if the node is healthy." }

        private let source: SystemDataSource

        init(source: SystemDataSource) {
            self.source = source
        }

        public func handle(request _: Request) async throws -> Response? {
            try await source.getHealth()
        }
    }

    struct Implementation: RPCHandler {
        public typealias Request = VoidRequest
        public typealias Response = String

        public static var method: String { "system_implementation" }
        public static var summary: String? { "Returns the implementation name of the node." }

        private let source: SystemDataSource

        init(source: SystemDataSource) {
            self.source = source
        }

        public func handle(request _: Request) async throws -> Response? {
            try await source.getImplementation()
        }
    }

    struct Version: RPCHandler {
        public typealias Request = VoidRequest
        public typealias Response = String

        public static var method: String { "system_version" }
        public static var summary: String? { "Returns the version of the node." }

        private let source: SystemDataSource

        init(source: SystemDataSource) {
            self.source = source
        }

        public func handle(request _: Request) async throws -> Response? {
            try await source.getVersion()
        }
    }

    struct Properties: RPCHandler {
        public typealias Request = VoidRequest
        public typealias Response = JSON

        public static var method: String { "system_properties" }
        public static var summary: String? { "Get a custom set of properties as a JSON object, defined in the chain spec." }

        private let source: SystemDataSource

        init(source: SystemDataSource) {
            self.source = source
        }

        public func handle(request _: Request) async throws -> Response? {
            try await source.getProperties()
        }
    }

    struct NodeRoles: RPCHandler {
        public typealias Request = VoidRequest
        public typealias Response = [String]

        public static var method: String { "system_nodeRoles" }
        public static var summary: String? { "Returns the roles the node is running as." }

        private let source: SystemDataSource

        init(source: SystemDataSource) {
            self.source = source
        }

        public func handle(request _: Request) async throws -> Response? {
            try await source.getNodeRoles()
        }
    }

    struct Chain: RPCHandler {
        public typealias Request = VoidRequest
        public typealias Response = String

        public static var method: String { "system_chain" }
        public static var summary: String? { "Returns the chain name, defined in the chain spec." }

        private let source: SystemDataSource

        init(source: SystemDataSource) {
            self.source = source
        }

        public func handle(request _: Request) async throws -> Response? {
            try await source.getChainName()
        }
    }
}
