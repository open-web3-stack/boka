private struct NoErrorMiddleware: MiddlewareProtocol {
    func handle<T: Sendable>(_ event: T, next: MiddlewareHandler<T>) async throws {
        do {
            try await next(event)
        } catch {
            assertionFailure("NoErrorMiddleware failed: \(error)")
        }
    }
}

extension Middleware {
    /// Asserts that no error is thrown by the next middleware
    /// NOTE: Used for testing only
    public static var noError: Middleware {
        Middleware(NoErrorMiddleware())
    }
}
