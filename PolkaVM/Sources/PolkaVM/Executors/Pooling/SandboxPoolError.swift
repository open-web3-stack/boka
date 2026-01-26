import Foundation

/// Errors that can occur in sandbox pool operations
public enum SandboxPoolError: Error {
    /// Pool is exhausted and queue is full
    case poolExhausted

    /// No workers available and queue is at capacity
    case queueFull

    /// Worker is not available (terminated or unhealthy)
    case workerNotAvailable

    /// Worker is busy and cannot accept new requests
    case workerBusy

    /// Worker failed to spawn
    case workerSpawnFailed(underlying: Error)

    /// Pool is marked as unhealthy
    case poolUnhealthy(reason: String)

    /// Request timed out
    case requestTimeout

    /// Configuration error
    case invalidConfiguration(reason: String)

    /// Worker execution failed
    case executionFailed(underlying: Error)

    /// Pool has been shut down
    case poolShutdown
}

extension SandboxPoolError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .poolExhausted:
            "All workers are busy and overflow is disabled"
        case .queueFull:
            "Request queue is at capacity"
        case .workerNotAvailable:
            "Worker is not available"
        case .workerBusy:
            "Worker is busy executing another request"
        case let .workerSpawnFailed(error):
            "Failed to spawn worker: \(error.localizedDescription)"
        case let .poolUnhealthy(reason):
            "Pool is unhealthy: \(reason)"
        case .requestTimeout:
            "Request timed out"
        case let .invalidConfiguration(reason):
            "Invalid configuration: \(reason)"
        case let .executionFailed(error):
            "Execution failed: \(error.localizedDescription)"
        case .poolShutdown:
            "Pool has been shut down"
        }
    }
}
