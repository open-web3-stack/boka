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
