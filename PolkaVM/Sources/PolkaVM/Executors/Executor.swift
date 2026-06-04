import Foundation
import Utils

public final class Executor: @unchecked Sendable {
    let config: PvmConfig
    let backend: ExecutorBackendJIT

    public init(config: PvmConfig) {
        self.config = config
        backend = ExecutorBackendJIT()
    }

    public func execute(
        blob: Data,
        pc: UInt32,
        gas: Gas,
        argumentData: Data?,
        ctx: (any InvocationContext)?,
    ) async -> VMExecutionResult {
        await backend.execute(
            config: config,
            blob: blob,
            pc: pc,
            gas: gas,
            argumentData: argumentData,
            ctx: ctx,
        )
    }
}
