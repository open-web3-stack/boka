import Foundation

enum TestLogger {
    static let setupOnce: () = {
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardError(label: label)
            handler.logLevel = .trace
            return handler
        }
    }()
}

/// Setup a logger for testing purposes
public func setupTestLogger() {
    TestLogger.setupOnce
}

#if !os(WASI)
public func withSpan<T>(
    _ operationName: String,
    logger: Logger,
    context: @autoclosure () -> ServiceContext = .current ?? .topLevel,
    ofKind kind: SpanKind = .internal,
    function: String = #function,
    file fileID: String = #fileID,
    line: UInt = #line,
    _ operation: (any Span) throws -> T?
) -> T? {
    withSpan(operationName, context: context(), ofKind: kind, function: function, file: fileID, line: line) { span in
        do {
            return try operation(span)
        } catch {
            logger.error("\(operationName) failed with unexpected error", metadata: ["error": "\(error)"])
            span.recordError(error)
            return nil
        }
    }
}

public func withSpan<T>(
    _ operationName: String,
    logger: Logger,
    context: @autoclosure () -> ServiceContext = .current ?? .topLevel,
    ofKind kind: SpanKind = .internal,
    function: String = #function,
    file fileID: String = #fileID,
    line: UInt = #line,
    _ operation: (any Span) async throws -> T?
) async -> T? {
    await withSpan(operationName, context: context(), ofKind: kind, function: function, file: fileID, line: line) { span in
        do {
            return try await operation(span)
        } catch {
            logger.error("\(operationName) failed with unexpected error", metadata: ["error": "\(error)"])
            span.recordError(error)
            return nil
        }
    }
}
#endif
