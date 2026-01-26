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
        self.workerID = workerID
        self.config = config
        ipcClient = IPCClient(timeout: config.executionTimeout)

        try await spawnWorker()
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
        guard isAlive else {
            throw SandboxPoolError.workerNotAvailable
        }

        guard !isBusy else {
            throw SandboxPoolError.workerBusy
        }

        isBusy = true
        defer { isBusy = false }

        let startTime = Date()

        do {
            // Send execution request
            let result = try await ipcClient.sendExecuteRequest(
                blob: blob,
                pc: pc,
                gas: gas.value,
                argumentData: argumentData,
                executionMode: executionMode
            )

            let executionTime = Date().timeIntervalSince(startTime)

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
                await recycle()
            }

            return VMExecutionResult(
                exitReason: result.exitReason,
                gasUsed: Gas(result.gasUsed),
                outputData: result.outputData
            )

        } catch {
            let executionTime = Date().timeIntervalSince(startTime)
            consecutiveFailures += 1

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

            logger.error("Worker \(workerID) execution failed: \(error)")
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
        let processManager = ChildProcessManager()

        let (handle, clientFD) = try await processManager.spawnChildProcess(
            executablePath: "boka-sandbox"
        )

        processHandle = handle
        ipcClient.setFileDescriptor(clientFD)
        isAlive = true
        startTime = Date()

        logger.debug("Worker \(workerID) spawned with PID \(handle.pid)")
    }

    /// Terminate the worker process
    private func terminate() async {
        guard let handle = processHandle else {
            return
        }

        logger.debug("Terminating worker \(workerID)")

        ipcClient.close()

        let processManager = ChildProcessManager()
        await processManager.kill(handle: handle)
        await processManager.reap(handle: handle)

        processHandle = nil
        isAlive = false
        isBusy = false
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
