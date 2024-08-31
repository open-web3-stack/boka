import Foundation

// TODO: Idea from https://github.com/apple/swift-log/pull/316, we may use that when it's released

// `nonisolated(unsafe)` added using compiler suggestion:
//     Disable concurrency-safety checks if accesses are protected by an external synchronization mechanism
// it's handled by `DispatchQueue` in this case
private nonisolated(unsafe) var isInitialized: Bool = false
private let loggerSetupQueue = DispatchQueue(label: "loggerSetupQueue")

/// Setup a logger for testing purposes
public func setupTestLogger(level: Logger.Level = .debug) {
    loggerSetupQueue.sync {
        if !isInitialized {
            LoggingSystem.bootstrap { label in
                var handler = StreamLogHandler.standardError(label: label)
                handler.logLevel = level
                return handler
            }
            isInitialized = true
        }
    }
}
