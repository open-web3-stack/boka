import TracingUtils

public final class LogMiddleware: MiddlewareProtocol {
    private let logger: Logger
    private let propagateError: Bool

    public init(logger: Logger, propagateError: Bool = false) {
        self.logger = logger
        self.propagateError = propagateError
    }

    public func handle<T>(_ event: T, next: MiddlewareHandler<T>) async throws {
        logger.debug(">>> dispatching event: \(event)")
        do {
            try await next(event)
            logger.debug("<<< event dispatched: \(event)")
        } catch {
            logger.error("<<! event dispatch failed: \(event) with error: \(error)")
            if propagateError {
                throw error
            }
        }
    }
}

extension Middleware {
    public static func log(logger: Logger) -> Middleware {
        Middleware(LogMiddleware(logger: logger))
    }
}
