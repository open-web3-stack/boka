import Foundation
import Utils

extension Executor {
    /// Create executor with sandbox pooling enabled
    public static func pooled(
        mode: ExecutionMode,
        config: PvmConfig = DefaultPvmConfig(),
        poolConfig: SandboxPoolConfiguration = .throughputOptimized
    ) -> Executor {
        let executor = Executor(mode: mode, config: config)

        // Replace frontend with pooled version if sandboxed
        if mode.contains(.sandboxed) {
            executor.frontend = ExecutorFrontendSandboxedWithPool(
                mode: mode,
                config: config,
                poolConfig: poolConfig
            )
        }

        return executor
    }
}
