import Foundation

/// Statistics for a sandbox worker
public struct SandboxWorkerStatistics: Sendable {
    /// Total number of executions handled by this worker
    public let totalExecutions: Int

    /// Number of successful executions
    public let successfulExecutions: Int

    /// Number of failed executions
    public let failedExecutions: Int

    /// Total execution time across all requests (seconds)
    public let totalExecutionTime: TimeInterval

    /// Average execution time per request (seconds)
    public var averageExecutionTime: TimeInterval {
        totalExecutions > 0 ? totalExecutionTime / TimeInterval(totalExecutions) : 0
    }

    /// Current execution count since last recycle
    public let currentExecutionCount: Int

    /// Whether worker is currently busy
    public let isBusy: Bool

    /// Worker health status
    public let health: WorkerHealth

    public init(
        totalExecutions: Int = 0,
        successfulExecutions: Int = 0,
        failedExecutions: Int = 0,
        totalExecutionTime: TimeInterval = 0,
        currentExecutionCount: Int = 0,
        isBusy: Bool = false,
        health: WorkerHealth = .healthy,
    ) {
        self.totalExecutions = totalExecutions
        self.successfulExecutions = successfulExecutions
        self.failedExecutions = failedExecutions
        self.totalExecutionTime = totalExecutionTime
        self.currentExecutionCount = currentExecutionCount
        self.isBusy = isBusy
        self.health = health
    }
}

/// Health status of a worker
public enum WorkerHealth: Sendable {
    case healthy
    case degraded(reason: String)
    case unhealthy(error: Error)
}

/// Pool-level statistics
public struct SandboxPoolStatistics: Sendable {
    /// Total number of workers in the pool
    public let totalWorkers: Int

    /// Number of active (busy) workers
    public let activeWorkers: Int

    /// Number of idle workers
    public let idleWorkers: Int

    /// Number of overflow workers (if enabled)
    public let overflowWorkers: Int

    /// Number of requests currently queued
    public let queuedRequests: Int

    /// Total number of executions handled by the pool
    public let totalExecutions: Int

    /// Total number of successful executions
    public let successfulExecutions: Int

    /// Total number of failed executions
    public let failedExecutions: Int

    /// Pool uptime in seconds
    public let uptime: TimeInterval

    /// Whether the pool is marked as unhealthy
    public let isHealthy: Bool

    /// Average queue wait time (seconds)
    public let averageQueueWaitTime: TimeInterval

    /// Worker failure rate (failures per minute in tracking window)
    public let workerFailureRate: Double

    public init(
        totalWorkers: Int = 0,
        activeWorkers: Int = 0,
        idleWorkers: Int = 0,
        overflowWorkers: Int = 0,
        queuedRequests: Int = 0,
        totalExecutions: Int = 0,
        successfulExecutions: Int = 0,
        failedExecutions: Int = 0,
        uptime: TimeInterval = 0,
        isHealthy: Bool = true,
        averageQueueWaitTime: TimeInterval = 0,
        workerFailureRate: Double = 0,
    ) {
        self.totalWorkers = totalWorkers
        self.activeWorkers = activeWorkers
        self.idleWorkers = idleWorkers
        self.overflowWorkers = overflowWorkers
        self.queuedRequests = queuedRequests
        self.totalExecutions = totalExecutions
        self.successfulExecutions = successfulExecutions
        self.failedExecutions = failedExecutions
        self.uptime = uptime
        self.isHealthy = isHealthy
        self.averageQueueWaitTime = averageQueueWaitTime
        self.workerFailureRate = workerFailureRate
    }

    /// Success rate as a percentage (0-100)
    public var successRate: Double {
        totalExecutions > 0
            ? Double(successfulExecutions) / Double(totalExecutions) * 100
            : 100
    }

    /// Pool utilization as a percentage (0-100)
    public var utilizationRate: Double {
        totalWorkers > 0
            ? Double(activeWorkers) / Double(totalWorkers) * 100
            : 0
    }
}
