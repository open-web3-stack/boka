public typealias MiddlewareHandler<T> = @Sendable (T) async throws -> Void

public protocol Middleware: Sendable {
    func handle<T: Sendable>(_ event: T, next: @escaping MiddlewareHandler<T>) async throws
}

private struct NoopMiddleware: Middleware {
    public func handle<T: Sendable>(_ event: T, next: MiddlewareHandler<T>) async throws {
        try await next(event)
    }
}

public enum Middlewares {
    public static var noop: some Middleware {
        NoopMiddleware()
    }
}
