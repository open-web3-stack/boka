import Foundation

/// Configuration for sandbox pool behavior
public struct SandboxPoolConfiguration: Sendable {
    /// Number of worker processes to maintain in the pool
    public var poolSize: Int

    /// Maximum number of concurrent requests to queue before rejecting
    public var maxQueueDepth: Int

    /// Timeout for waiting for an available worker (seconds)
    public var workerWaitTimeout: TimeInterval

    /// Timeout for individual PVM execution (seconds)
    public var executionTimeout: TimeInterval

    /// Whether to enable periodic worker recycling to prevent memory leaks
    public var enableWorkerRecycling: Bool

    /// Number of executions after which a worker is recycled (if enabled)
    public var workerRecycleThreshold: Int

    /// Health check interval in seconds (0 = disabled)
    public var healthCheckInterval: TimeInterval

    /// Maximum consecutive worker failures before marking pool unhealthy
    public var maxConsecutiveFailures: Int

    /// Time window for failure tracking (seconds)
    public var failureTrackingWindow: TimeInterval

    /// Whether to spawn overflow workers when pool is exhausted
    public var allowOverflowWorkers: Bool

    /// Maximum number of overflow workers (0 = unlimited)
    public var maxOverflowWorkers: Int

    /// Pool exhaustion policy
    public var exhaustionPolicy: ExhaustionPolicy

    /// Path to the boka-sandbox executable
    public var sandboxPath: String

    public init(
        poolSize: Int = ProcessInfo.processInfo.processorCount,
        maxQueueDepth: Int = 1000,
        workerWaitTimeout: TimeInterval = 30.0,
        executionTimeout: TimeInterval = 120.0,
        enableWorkerRecycling: Bool = true,
        workerRecycleThreshold: Int = 10000,
        healthCheckInterval: TimeInterval = 0.0,
        maxConsecutiveFailures: Int = 3,
        failureTrackingWindow: TimeInterval = 60.0,
        allowOverflowWorkers: Bool = false,
        maxOverflowWorkers: Int = 0,
        exhaustionPolicy: ExhaustionPolicy = .queue,
        sandboxPath: String = "boka-sandbox",
    ) {
        self.poolSize = poolSize
        self.maxQueueDepth = maxQueueDepth
        self.workerWaitTimeout = workerWaitTimeout
        self.executionTimeout = executionTimeout
        self.enableWorkerRecycling = enableWorkerRecycling
        self.workerRecycleThreshold = workerRecycleThreshold
        self.healthCheckInterval = healthCheckInterval
        self.maxConsecutiveFailures = maxConsecutiveFailures
        self.failureTrackingWindow = failureTrackingWindow
        self.allowOverflowWorkers = allowOverflowWorkers
        self.maxOverflowWorkers = maxOverflowWorkers
        self.exhaustionPolicy = exhaustionPolicy
        self.sandboxPath = sandboxPath == "boka-sandbox"
            ? SandboxExecutableResolver.resolve().path
            : sandboxPath
    }

    /// Default configuration optimized for throughput
    public static var throughputOptimized: SandboxPoolConfiguration {
        SandboxPoolConfiguration(
            poolSize: ProcessInfo.processInfo.processorCount * 2,
            maxQueueDepth: 10000,
            workerWaitTimeout: 60.0,
            executionTimeout: 120.0,
            enableWorkerRecycling: true,
            workerRecycleThreshold: 50000,
            healthCheckInterval: 0.0, // Disabled for max throughput
            allowOverflowWorkers: true,
            maxOverflowWorkers: ProcessInfo.processInfo.processorCount,
            exhaustionPolicy: .queue,
        )
    }

    /// Default configuration optimized for latency
    public static var latencyOptimized: SandboxPoolConfiguration {
        SandboxPoolConfiguration(
            poolSize: ProcessInfo.processInfo.processorCount,
            maxQueueDepth: 100,
            workerWaitTimeout: 5.0,
            executionTimeout: 30.0,
            enableWorkerRecycling: false, // Keep workers warm
            workerRecycleThreshold: 0,
            healthCheckInterval: 1.0,
            allowOverflowWorkers: false,
            maxOverflowWorkers: 0,
            exhaustionPolicy: .failFast,
        )
    }

    /// Default configuration optimized for memory efficiency
    public static var memoryEfficient: SandboxPoolConfiguration {
        SandboxPoolConfiguration(
            poolSize: max(2, ProcessInfo.processInfo.processorCount / 2),
            maxQueueDepth: 500,
            workerWaitTimeout: 30.0,
            executionTimeout: 120.0,
            enableWorkerRecycling: true,
            workerRecycleThreshold: 1000,
            healthCheckInterval: 5.0,
            allowOverflowWorkers: false,
            maxOverflowWorkers: 0,
            exhaustionPolicy: .queue,
        )
    }

    /// Conservative configuration for development/testing
    public static var development: SandboxPoolConfiguration {
        SandboxPoolConfiguration(
            poolSize: 2,
            maxQueueDepth: 100,
            workerWaitTimeout: 10.0,
            executionTimeout: 30.0,
            enableWorkerRecycling: false,
            workerRecycleThreshold: 100,
            healthCheckInterval: 1.0,
            allowOverflowWorkers: false,
            maxOverflowWorkers: 0,
            exhaustionPolicy: .failFast,
        )
    }
}

/// Policy for handling requests when all workers are busy
public enum ExhaustionPolicy: Sendable {
    /// Queue the request and wait for available worker
    case queue

    /// Fail immediately with an error
    case failFast

    /// Spawn temporary overflow worker (if enabled)
    case spawnOverflow
}
