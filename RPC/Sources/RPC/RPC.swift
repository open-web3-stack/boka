// The Swift Programming Language
// https://docs.swift.org/swift-book
import Vapor

public func startServer() throws {
    let env = try Environment.detect()
    let app = Application(env)
    defer { app.shutdown() }
    try configure(app)
    try app.run()
}

public func configure(_ app: Application) throws {
    // Register routes
    let rpcController = RPCController()
    try app.register(collection: rpcController)
}
