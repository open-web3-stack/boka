import Foundation
import TracingUtils
import Utils

final class ExecutorFrontendSandboxedWithPool: ExecutorFrontend {
    private let logger = Logger(label: "ExecutorFrontendSandboxedWithPool")
    private let mode: ExecutionMode
    private let config: PvmConfig
    private let poolConfig: SandboxPoolConfiguration

    // Pool instance (lazy initialized)
    private var pool: SandboxPool?

    // Protocol requirement
    required convenience init(mode: ExecutionMode) {
        self.init(mode: mode, config: DefaultPvmConfig(), poolConfig: .throughputOptimized)
    }

    init(mode: ExecutionMode, config: PvmConfig = DefaultPvmConfig(), poolConfig: SandboxPoolConfiguration = .throughputOptimized) {
        self.mode = mode
        self.config = config
        self.poolConfig = poolConfig
    }

    func execute(
        config _: PvmConfig,
        blob: Data,
        pc: UInt32,
        gas: Gas,
        argumentData: Data?,
        ctx: (any InvocationContext)?
    ) async -> VMExecutionResult {
        logger.debug("[Frontend] execute() called - ctx: \(ctx != nil ? "non-nil" : "nil")")

        // Sandboxed mode does not support InvocationContext
        // Fall back to in-process execution when context is provided
        if ctx != nil {
            logger.warning("Sandboxed mode does not support InvocationContext yet - falling back to in-process execution")
            // Use in-process executor as fallback
            let inProcessFrontend = ExecutorFrontendInProcess(mode: mode)
            return await inProcessFrontend.execute(
                config: config,
                blob: blob,
                pc: pc,
                gas: gas,
                argumentData: argumentData,
                ctx: ctx
            )
        }

        logger.debug("[Frontend] Context check passed, getting pool...")

        do {
            // Get or create pool
            let pool = try await getPool()
            logger.debug("[Frontend] Pool obtained, executing...")

            // Execute using pool
            // Note: ctx is always nil here (checked above), so passing nil is safe
            return try await pool.execute(
                blob: blob,
                pc: pc,
                gas: gas,
                argumentData: argumentData,
                ctx: nil
            )

        } catch {
            logger.error("Pooled sandboxed execution failed: \(error)")

            // Return error result
            return VMExecutionResult(
                exitReason: .panic(.trap),
                gasUsed: Gas(0),
                outputData: nil
            )
        }
    }

    /// Get or create the sandbox pool
    private func getPool() async throws -> SandboxPool {
        if let pool {
            return pool
        }

        let newPool = try await SandboxPool(
            config: poolConfig,
            executionMode: mode
        )
        pool = newPool
        return newPool
    }

    /// Get pool statistics
    func getPoolStatistics() async -> SandboxPoolStatistics? {
        await pool?.getStatistics()
    }

    /// Shutdown the pool
    func shutdown() async {
        await pool?.shutdown()
        pool = nil
    }

    deinit {
        // Note: Can't call async shutdown() from deinit
        // Pool will be cleaned up when workers are terminated
    }
}
