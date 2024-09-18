import TracingUtils

public final class LogMiddleware: Middleware {
    private let logger: Logger

    public init(logger: Logger) {
        self.logger = logger
    }

    public func handle<T>(_ event: T, next: MiddlewareHandler<T>) async throws {
        logger.debug(">>> dispatching event: \(event)")
        do {
            try await next(event)
            logger.debug("<<< event dispatched: \(event)")
        } catch {
            logger.error("<<! event dispatch failed: \(event) with error: \(error)")
            throw error
        }
    }
}
