import TracingUtils

public final class TracingMiddleware: Middleware {
    public func handle<T>(_ event: T, next: MiddlewareHandler<T>) async throws {
        try await withSpan(String(describing: type(of: event))) { span in
            span.attributes.event = String(describing: event)
            try await next(event)
        }
    }
}
