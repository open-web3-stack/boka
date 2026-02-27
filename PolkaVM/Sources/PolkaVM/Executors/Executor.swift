import Foundation
import Utils

public final class Executor: @unchecked Sendable {
    let mode: ExecutionMode
    let config: PvmConfig
    let sandboxPath: String

    var frontend: ExecutorFrontend

    public init(mode: ExecutionMode, config: PvmConfig) {
        self.mode = mode
        self.config = config
        sandboxPath = SandboxExecutableResolver.resolve().path

        if mode.contains(.sandboxed) {
            frontend = ExecutorFrontendSandboxed(mode: mode)
        } else {
            frontend = ExecutorFrontendInProcess(mode: mode)
        }
    }

    public func execute(
        blob: Data,
        pc: UInt32,
        gas: Gas,
        argumentData: Data?,
        ctx: (any InvocationContext)?,
    ) async -> VMExecutionResult {
        return await frontend.execute(
            config: config,
            blob: blob,
            pc: pc,
            gas: gas,
            argumentData: argumentData,
            ctx: ctx,
        )
    }

    /// Shutdown the executor and clean up resources
    /// For pooled executors, this terminates all worker processes
    public func shutdown() async {
        // If using pooled sandbox frontend, shut down the pool
        if let pooledFrontend = frontend as? ExecutorFrontendSandboxedWithPool {
            await pooledFrontend.shutdown()
        }
    }

    deinit {
        // Note: Can't call async shutdown() from deinit
        // Resources will be cleaned up via deinits of child actors
        // Tests should explicitly call shutdown() for clean cleanup
    }
}
