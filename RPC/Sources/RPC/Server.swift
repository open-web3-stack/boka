import Foundation
import Vapor

public class Server {
    public enum Error: Swift.Error {
        case invalidListenAddress(address: String)
    }

    public class Config {
        public let listenAddress: String
        public let port: Int

        public init(listenAddress: String, port: Int) {
            self.listenAddress = listenAddress
            self.port = port
        }
    }

    private let config: Config
    private let source: DataSource
    private let app: Application

    public init(config: Config, source: DataSource) throws {
        self.config = config
        self.source = source
        // TODO: add env to arguments
        let env = try Environment.detect(arguments: ["--env"])
        app = Application(env)

        var handlers: [String: JSONRPCHandler] = SystemHandler.getHandlers()
        handlers.merge(ChainHandler.getHandlers(source: source)) { _, new in new }
        handlers.merge(TelemetryHandler.getHandlers(source: source)) { _, new in new }

        // Register routes
        let rpcController = JSONRPCController(handlers: handlers)
        try app.register(collection: rpcController)

        app.http.server.configuration.address = .hostname(config.listenAddress, port: config.port)

        try app.start()
    }

    deinit {
        app.shutdown()
    }

    public func wait() async throws {
        try await app.running?.onStop.get()
    }
}
