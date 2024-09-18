private typealias Handler = @Sendable (Any) async throws -> Void

public final class SerialDispatcher: Middleware {
    private let middlewares: [Middleware]

    public init(middlewares: [Middleware]) {
        self.middlewares = middlewares
    }

    public func handle<T: Sendable>(_ event: T, next: @escaping MiddlewareHandler<T>) async throws {
        var next = next
        for middleware in middlewares.reversed() {
            let next2 = next
            next = { event in
                try await middleware.handle(event, next: next2)
            }
        }
        try await next(event)
    }
}

public struct ParallelDispatcherError: Error {
    public var errors: [(index: Int, error: Error)]
}

public final class ParallelDispatcher: Middleware {
    private let middlewares: [Middleware]

    public init(middlewares: [Middleware]) {
        self.middlewares = middlewares
    }

    public func handle<T: Sendable>(_ event: T, next: @escaping MiddlewareHandler<T>) async throws {
        var error = ParallelDispatcherError(errors: [])

        await withTaskGroup(of: (index: Int, error: Error)?.self) { group in
            for (idx, middleware) in middlewares.enumerated() {
                group.addTask { () -> (index: Int, error: Error)? in
                    let res = await Result { try await middleware.handle(event, next: next) }
                    switch res {
                    case .success:
                        return Optional.none
                    case let .failure(err):
                        return (index: idx, error: err)
                    }
                }
            }

            for await result in group {
                if let result {
                    error.errors.append(result)
                }
            }
        }

        if !error.errors.isEmpty {
            throw error
        }
    }
}

extension Middlewares {
    public static func serial(_ middlewares: Middleware...) -> some Middleware {
        SerialDispatcher(middlewares: middlewares)
    }

    @_disfavoredOverload
    public static func serial(_ middlewares: [Middleware]) -> some Middleware {
        SerialDispatcher(middlewares: middlewares)
    }

    public static func parallel(_ middlewares: Middleware...) -> some Middleware {
        ParallelDispatcher(middlewares: middlewares)
    }

    @_disfavoredOverload
    public static func parallel(_ middlewares: [Middleware]) -> some Middleware {
        ParallelDispatcher(middlewares: middlewares)
    }
}
