import TracingUtils

public final class TracingMiddleware: MiddlewareProtocol {
    public let prefix: String?

    public init(prefix: String? = nil) {
        self.prefix = prefix
    }

    public func handle<T>(_ event: T, next: MiddlewareHandler<T>) async throws {
        try await withSpan(String(describing: type(of: event))) { span in
            span.attributes.event = String(describing: event)
            try await next(event)
        }
    }
}

extension Middleware {
    public static func tracing(prefix: String? = nil) -> Middleware {
        Middleware(TracingMiddleware(prefix: prefix))
    }
}
