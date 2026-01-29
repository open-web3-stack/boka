import Foundation
import TracingUtils
import Utils
#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

/// Actor managing a single sandbox worker process
actor SandboxWorker {
    private let logger = Logger(label: "SandboxWorker")
    private let config: SandboxPoolConfiguration
    private let workerID: UInt32

    // Process management
    private var processHandle: ProcessHandle?
    private var processManager = ChildProcessManager()
    private var ipcClient: IPCClient
    private var isAlive = false
    private var isBusy = false

    // Statistics
    private var stats = SandboxWorkerStatistics()
    private var executionCountSinceRecycle = 0
    private var consecutiveFailures = 0
    private var failureTimestamps: [TimeInterval] = []

    // Lifecycle
    private var startTime = Date()

    /// Get the worker ID (for pool management)
    var id: UInt32 {
        workerID
    }

    init(workerID: UInt32, config: SandboxPoolConfiguration) async throws {
        logger.debug("[INIT] Worker \(workerID): Initializing with config")
        self.workerID = workerID
        self.config = config
        ipcClient = IPCClient(timeout: config.executionTimeout)

        logger.debug("[INIT] Worker \(workerID): Spawning worker process")
        try await spawnWorker()
        logger.debug("[INIT] Worker \(workerID): Initialization complete")
    }

    // MARK: - Public API

    /// Execute a PVM program in this worker
    func execute(
        blob: Data,
        pc: UInt32,
        gas: Gas,
        argumentData: Data?,
        executionMode: ExecutionMode
    ) async throws -> VMExecutionResult {
        logger.debug("[EXEC] Worker \(workerID): execute() called - isAlive=\(isAlive), isBusy=\(isBusy)")

        guard isAlive else {
            logger.error("[EXEC] Worker \(workerID): Not alive, cannot execute")
            throw SandboxPoolError.workerNotAvailable
        }

        guard !isBusy else {
            logger.warning("[EXEC] Worker \(workerID): Already busy, rejecting request")
            throw SandboxPoolError.workerBusy
        }

        isBusy = true
        logger.debug("[EXEC] Worker \(workerID): Marked as busy")
        defer {
            isBusy = false
            logger.debug("[EXEC] Worker \(workerID): Marked as not busy")
        }

        let startTime = Date()

        do {
            logger.debug("[EXEC] Worker \(workerID): Sending IPC request - blob size=\(blob.count), gas=\(gas.value)")

            // Send execution request
            let result = try await ipcClient.sendExecuteRequest(
                blob: blob,
                pc: pc,
                gas: gas.value,
                argumentData: argumentData,
                executionMode: executionMode
            )

            let executionTime = Date().timeIntervalSince(startTime)
            logger
                .debug(
                    "[EXEC] Worker \(workerID): Got result in \(String(format: "%.2f", executionTime * 1000))ms - exitReason=\(result.exitReason)"
                )

            // Update statistics
            executionCountSinceRecycle += 1
            stats = SandboxWorkerStatistics(
                totalExecutions: stats.totalExecutions + 1,
                successfulExecutions: stats.successfulExecutions + 1,
                failedExecutions: stats.failedExecutions,
                totalExecutionTime: stats.totalExecutionTime + executionTime,
                currentExecutionCount: executionCountSinceRecycle,
                isBusy: false,
                health: .healthy
            )

            consecutiveFailures = 0

            // Check if worker should be recycled
            if config.enableWorkerRecycling,
               executionCountSinceRecycle >= config.workerRecycleThreshold
            {
                logger
                    .debug(
                        "[EXEC] Worker \(workerID): Execution count \(executionCountSinceRecycle) >= threshold \(config.workerRecycleThreshold), recycling"
                    )
                await recycle()
            }

            logger
                .info(
                    "[EXEC] Worker \(workerID): Execution successful (total: \(stats.totalExecutions), failures: \(stats.failedExecutions))"
                )

            return VMExecutionResult(
                exitReason: result.exitReason,
                gasUsed: Gas(result.gasUsed),
                outputData: result.outputData
            )

        } catch {
            let executionTime = Date().timeIntervalSince(startTime)
            consecutiveFailures += 1

            logger.error("[EXEC] Worker \(workerID): Execution failed after \(String(format: "%.2f", executionTime * 1000))ms - \(error)")

            // Track failure timestamp
            failureTimestamps.append(Date().timeIntervalSince1970)
            cleanupOldFailures()

            // Update statistics with failure
            stats = SandboxWorkerStatistics(
                totalExecutions: stats.totalExecutions + 1,
                successfulExecutions: stats.successfulExecutions,
                failedExecutions: stats.failedExecutions + 1,
                totalExecutionTime: stats.totalExecutionTime + executionTime,
                currentExecutionCount: executionCountSinceRecycle,
                isBusy: false,
                health: .degraded(reason: "\(error)")
            )

            // Check if worker should be marked unhealthy
            if consecutiveFailures >= config.maxConsecutiveFailures {
                logger.error("[EXEC] Worker \(workerID): Marked as unhealthy after \(consecutiveFailures) consecutive failures")
                stats = SandboxWorkerStatistics(
                    totalExecutions: stats.totalExecutions,
                    successfulExecutions: stats.successfulExecutions,
                    failedExecutions: stats.failedExecutions,
                    totalExecutionTime: stats.totalExecutionTime,
                    currentExecutionCount: executionCountSinceRecycle,
                    isBusy: false,
                    health: .unhealthy(error: error)
                )
            }

            throw error
        }
    }

    /// Get current statistics
    func getStatistics() -> SandboxWorkerStatistics {
        stats
    }

    /// Check if worker is healthy
    func isHealthy() -> Bool {
        if case .unhealthy = stats.health {
            return false
        }
        return true
    }

    /// Check if worker should be recycled based on failure rate
    func shouldRecycle() -> Bool {
        // Check consecutive failures
        if consecutiveFailures >= config.maxConsecutiveFailures {
            return true
        }

        // Check failure rate in tracking window
        if failureTimestamps.count >= config.maxConsecutiveFailures {
            let windowStart = Date().timeIntervalSince1970 - config.failureTrackingWindow
            let recentFailures = failureTimestamps.filter { $0 >= windowStart }
            if recentFailures.count >= config.maxConsecutiveFailures {
                return true
            }
        }

        // Check execution count threshold
        if config.enableWorkerRecycling,
           executionCountSinceRecycle >= config.workerRecycleThreshold
        {
            return true
        }

        return false
    }

    // MARK: - Lifecycle Management

    /// Recycle the worker (kill and respawn)
    private func recycle() async {
        logger.debug("Recycling worker \(workerID)")

        await terminate()

        do {
            try await spawnWorker()
            executionCountSinceRecycle = 0
            consecutiveFailures = 0
            failureTimestamps.removeAll()
        } catch {
            logger.error("Failed to respawn worker \(workerID): \(error)")
        }
    }

    /// Spawn a new worker process
    private func spawnWorker() async throws {
        logger.debug("[SPAWN] Worker \(workerID): Starting spawn process")

        logger.debug("[SPAWN] Worker \(workerID): Calling spawnChildProcess")
        let (handle, clientFD) = try await processManager.spawnChildProcess(
            executablePath: config.sandboxPath
        )

        logger.debug("[SPAWN] Worker \(workerID): Got handle PID=\(handle.pid), clientFD=\(clientFD)")

        processHandle = handle
        ipcClient.setFileDescriptor(clientFD)
        isAlive = true
        startTime = Date()

        logger.debug("[SPAWN] Worker \(workerID): Spawned successfully with PID \(handle.pid), isAlive=\(isAlive)")
    }

    /// Terminate the worker process
    func terminate() async {
        guard let handle = processHandle else {
            logger.debug("[TERM] Worker \(workerID): No process handle to terminate")
            return
        }

        logger.debug("[TERM] Worker \(workerID): Terminating PID \(handle.pid)")

        ipcClient.close()
        logger.debug("[TERM] Worker \(workerID): IPC client closed")

        await processManager.kill(handle: handle)
        logger.debug("[TERM] Worker \(workerID): Process killed")

        await processManager.reap(handle: handle)
        logger.debug("[TERM] Worker \(workerID): Process reaped")

        processHandle = nil
        isAlive = false
        isBusy = false

        logger.debug("[TERM] Worker \(workerID): Termination complete, isAlive=\(isAlive)")
    }

    /// Cleanup old failure timestamps outside tracking window
    private func cleanupOldFailures() {
        let windowStart = Date().timeIntervalSince1970 - config.failureTrackingWindow
        failureTimestamps = failureTimestamps.filter { $0 >= windowStart }
    }

    nonisolated deinit {
        // Note: Can't call async terminate() from deinit
        // Process cleanup will happen via ChildProcessManager deinit
        // or through explicit shutdown
    }
}
