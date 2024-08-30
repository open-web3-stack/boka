/// Setup a logger for testing purposes
public func setupTestLogger(level: Logger.Level = .debug) {
    LoggingSystem.bootstrap { label in
        var handler = StreamLogHandler.standardError(label: label)
        handler.logLevel = level
        return handler
    }
}
