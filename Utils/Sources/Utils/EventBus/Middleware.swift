public typealias MiddlewareHandler<T> = @Sendable (T) async throws -> Void

public protocol MiddlewareProtocol: Sendable {
    func handle<T: Sendable>(_ event: T, next: @escaping MiddlewareHandler<T>) async throws
}

public struct Middleware: MiddlewareProtocol {
    private let impl: any MiddlewareProtocol

    public init(_ impl: any MiddlewareProtocol) {
        self.impl = impl
    }

    public func handle<T: Sendable>(_ event: T, next: @escaping MiddlewareHandler<T>) async throws {
        try await impl.handle(event, next: next)
    }
}

private struct NoopMiddleware: MiddlewareProtocol {
    func handle<T: Sendable>(_ event: T, next: MiddlewareHandler<T>) async throws {
        try await next(event)
    }
}

extension Middleware {
    public static var noop: Middleware {
        Middleware(NoopMiddleware())
    }
}
