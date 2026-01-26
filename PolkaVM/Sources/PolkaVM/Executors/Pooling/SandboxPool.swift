import Foundation
import TracingUtils
import Utils
#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

/// Actor managing a pool of sandbox worker processes
public actor SandboxPool {
    private let logger = Logger(label: "SandboxPool")
    private let config: SandboxPoolConfiguration
    private let executionMode: ExecutionMode

    // Worker management
    private var workers: [UInt32: SandboxWorker] = [:]
    private var nextWorkerID: UInt32 = 0
    private var overflowWorkers: Int = 0

    // Request tracking
    private var activeRequests = 0

    // Statistics
    private var stats = SandboxPoolStatistics()
    private var startTime = Date()
    private var totalExecutions = 0
    private var successfulExecutions = 0
    private var failedExecutions = 0

    // Lifecycle
    private var isShutdown = false
    private var isHealthy = true
    private var unhealthyReason: String?

    // Queue wait time tracking
    private var queueWaitTimes: [TimeInterval] = []

    public init(config: SandboxPoolConfiguration, executionMode: ExecutionMode) async throws {
        self.config = config
        self.executionMode = executionMode

        // Validate configuration
        try validateConfiguration()

        // Spawn initial workers
        try await spawnInitialWorkers()

        logger.info("Sandbox pool initialized with \(config.poolSize) workers")

        // Start health check task if enabled
        if config.healthCheckInterval > 0 {
            Task {
                await runHealthChecks()
            }
        }
    }

    // MARK: - Public API

    /// Execute a PVM program using an available worker from the pool
    public func execute(
        blob: Data,
        pc: UInt32,
        gas: Gas,
        argumentData: Data?,
        ctx _: (any InvocationContext)?
    ) async throws -> VMExecutionResult {
        guard !isShutdown else {
            throw SandboxPoolError.poolShutdown
        }

        guard isHealthy else {
            throw SandboxPoolError.poolUnhealthy(reason: unhealthyReason ?? "Unknown")
        }

        // Enqueue request
        let startTime = Date()

        // Try to get an available worker
        guard let worker = try await getAvailableWorker() else {
            // Handle pool exhaustion
            return try await handleExhaustion(
                blob: blob,
                pc: pc,
                gas: gas,
                argumentData: argumentData
            )
        }

        // Track queue wait time
        let queueWaitTime = Date().timeIntervalSince(startTime)
        trackQueueWaitTime(queueWaitTime)

        // Execute the request
        do {
            let result = try await worker.execute(
                blob: blob,
                pc: pc,
                gas: gas,
                argumentData: argumentData,
                executionMode: executionMode
            )

            totalExecutions += 1
            successfulExecutions += 1
            activeRequests -= 1

            // Check if worker needs recycling
            if await worker.shouldRecycle() {
                Task {
                    await recycleWorker(worker)
                }
            }

            return result

        } catch {
            totalExecutions += 1
            failedExecutions += 1
            activeRequests -= 1

            // Check if error indicates worker failure
            if isWorkerFailure(error) {
                Task {
                    await recycleWorker(worker)
                }
            }

            throw SandboxPoolError.executionFailed(underlying: error)
        }
    }

    /// Get current pool statistics
    public func getStatistics() -> SandboxPoolStatistics {
        let uptime = Date().timeIntervalSince(startTime)

        let averageQueueWait: TimeInterval = if queueWaitTimes.isEmpty {
            0
        } else {
            queueWaitTimes.reduce(0, +) / Double(queueWaitTimes.count)
        }

        // Calculate failure rate
        let failureRate = calculateFailureRate()

        return SandboxPoolStatistics(
            totalWorkers: workers.count + overflowWorkers,
            activeWorkers: activeRequests,
            idleWorkers: workers.count - activeRequests,
            overflowWorkers: overflowWorkers,
            queuedRequests: 0, // Queue management not yet implemented
            totalExecutions: totalExecutions,
            successfulExecutions: successfulExecutions,
            failedExecutions: failedExecutions,
            uptime: uptime,
            isHealthy: isHealthy,
            averageQueueWaitTime: averageQueueWait,
            workerFailureRate: failureRate
        )
    }

    /// Gracefully shutdown the pool
    public func shutdown() async {
        logger.info("Shutting down sandbox pool...")
        isShutdown = true

        // Terminate all workers
        for _ in workers.values {
            // Workers will be terminated in their deinit
        }

        workers.removeAll()

        logger.info("Sandbox pool shutdown complete")
    }

    // MARK: - Private Methods

    /// Validate configuration
    private func validateConfiguration() throws {
        guard config.poolSize > 0 else {
            throw SandboxPoolError.invalidConfiguration(reason: "poolSize must be > 0")
        }

        guard config.maxQueueDepth >= 0 else {
            throw SandboxPoolError.invalidConfiguration(reason: "maxQueueDepth must be >= 0")
        }

        guard config.workerWaitTimeout > 0 else {
            throw SandboxPoolError.invalidConfiguration(reason: "workerWaitTimeout must be > 0")
        }

        guard config.executionTimeout > 0 else {
            throw SandboxPoolError.invalidConfiguration(reason: "executionTimeout must be > 0")
        }
    }

    /// Spawn initial pool workers
    private func spawnInitialWorkers() async throws {
        for _ in 0 ..< config.poolSize {
            let workerID = nextWorkerID
            nextWorkerID += 1

            do {
                let worker = try await SandboxWorker(
                    workerID: workerID,
                    config: config
                )
                workers[workerID] = worker
            } catch {
                logger.error("Failed to spawn worker \(workerID): \(error)")
                throw SandboxPoolError.workerSpawnFailed(underlying: error)
            }
        }
    }

    /// Get an available worker from the pool
    private func getAvailableWorker() async throws -> SandboxWorker? {
        // Try to find an idle worker
        for (_, worker) in workers {
            if await !worker.getStatistics().isBusy {
                return worker
            }
        }

        // No idle workers - check exhaustion policy
        switch config.exhaustionPolicy {
        case .queue:
            // Wait for available worker
            return try await waitForAvailableWorker()

        case .failFast:
            return nil

        case .spawnOverflow:
            if config.allowOverflowWorkers,
               config.maxOverflowWorkers == 0 || overflowWorkers < config.maxOverflowWorkers
            {
                return try await spawnOverflowWorker()
            }
            return nil
        }
    }

    /// Wait for an available worker
    private func waitForAvailableWorker() async throws -> SandboxWorker? {
        // Simple polling implementation (TODO: replace with proper queue)
        let deadline = Date().addingTimeInterval(config.workerWaitTimeout)

        while Date() < deadline {
            // Check for idle worker
            for (_, worker) in workers {
                if await !worker.getStatistics().isBusy {
                    return worker
                }
            }

            // Wait a bit before checking again
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }

        // Timeout
        throw SandboxPoolError.requestTimeout
    }

    /// Spawn an overflow worker
    private func spawnOverflowWorker() async throws -> SandboxWorker {
        let workerID = nextWorkerID
        nextWorkerID += 1

        logger.debug("Spawning overflow worker \(workerID)")

        do {
            let worker = try await SandboxWorker(
                workerID: workerID,
                config: config
            )
            workers[workerID] = worker
            overflowWorkers += 1
            return worker
        } catch {
            logger.error("Failed to spawn overflow worker: \(error)")
            throw SandboxPoolError.workerSpawnFailed(underlying: error)
        }
    }

    /// Handle pool exhaustion
    private func handleExhaustion(
        blob: Data,
        pc: UInt32,
        gas: Gas,
        argumentData: Data?
    ) async throws -> VMExecutionResult {
        switch config.exhaustionPolicy {
        case .queue:
            throw SandboxPoolError.queueFull

        case .failFast:
            throw SandboxPoolError.poolExhausted

        case .spawnOverflow:
            if config.allowOverflowWorkers {
                let worker = try await spawnOverflowWorker()
                return try await worker.execute(
                    blob: blob,
                    pc: pc,
                    gas: gas,
                    argumentData: argumentData,
                    executionMode: executionMode
                )
            }
            throw SandboxPoolError.poolExhausted
        }
    }

    /// Recycle a worker
    private func recycleWorker(_ worker: SandboxWorker) async {
        // Worker will recycle itself
        // Just need to remove from pool and spawn replacement

        // Find the worker ID by looking through the dictionary
        var workerID: UInt32?
        for (id, w) in workers {
            if w === worker {
                workerID = id
                break
            }
        }

        guard let id = workerID else {
            logger.warning("Could not find worker ID for recycling")
            return
        }

        logger.debug("Recycling worker \(id)")

        workers.removeValue(forKey: id)

        if id < UInt32(config.poolSize) {
            // Spawn replacement for core worker
            do {
                let newWorker = try await SandboxWorker(
                    workerID: nextWorkerID,
                    config: config
                )
                nextWorkerID += 1
                let newWorkerID = await newWorker.id
                workers[newWorkerID] = newWorker
            } catch {
                logger.error("Failed to spawn replacement worker: \(error)")
            }
        } else {
            // Don't replace overflow workers
            overflowWorkers -= 1
        }
    }

    /// Run periodic health checks
    private func runHealthChecks() async {
        while !isShutdown {
            try? await Task.sleep(nanoseconds: UInt64(config.healthCheckInterval * 1_000_000_000))

            await checkWorkerHealth()
        }
    }

    /// Check health of all workers
    private func checkWorkerHealth() async {
        var unhealthyCount = 0

        for (id, worker) in workers {
            let healthy = await worker.isHealthy()
            if !healthy {
                unhealthyCount += 1
                logger.warning("Worker \(id) is unhealthy")
                Task {
                    await recycleWorker(worker)
                }
            }
        }

        // Mark pool unhealthy if too many workers are unhealthy
        if unhealthyCount > workers.count / 2 {
            isHealthy = false
            unhealthyReason = "\(unhealthyCount) workers are unhealthy"
            logger.error("Pool marked as unhealthy: \(unhealthyReason ?? "")")
        }
    }

    /// Check if error indicates worker failure
    private func isWorkerFailure(_ error: Error) -> Bool {
        if let ipcError = error as? IPCError {
            switch ipcError {
            case .unexpectedEOF, .readFailed, .writeFailed, .timeout:
                return true
            default:
                return false
            }
        }
        return false
    }

    /// Calculate failure rate per minute
    private func calculateFailureRate() -> Double {
        let timeWindow = config.failureTrackingWindow
        let totalExecutionsInWindow = Double(totalExecutions)

        if totalExecutionsInWindow == 0 {
            return 0
        }

        let failedExecutionsInWindow = Double(failedExecutions)
        return (failedExecutionsInWindow / totalExecutionsInWindow) * (60.0 / timeWindow)
    }

    /// Track queue wait time
    private func trackQueueWaitTime(_ time: TimeInterval) {
        queueWaitTimes.append(time)

        // Keep only last 1000 samples
        if queueWaitTimes.count > 1000 {
            queueWaitTimes.removeFirst(queueWaitTimes.count - 1000)
        }
    }
}
