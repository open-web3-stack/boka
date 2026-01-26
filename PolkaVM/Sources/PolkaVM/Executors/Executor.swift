import Foundation
import Utils

public final class Executor: @unchecked Sendable {
    let mode: ExecutionMode
    let config: PvmConfig

    var frontend: ExecutorFrontend

    public init(mode: ExecutionMode, config: PvmConfig) {
        self.mode = mode
        self.config = config

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
        ctx: (any InvocationContext)?
    ) async -> VMExecutionResult {
        await frontend.execute(
            config: config,
            blob: blob,
            pc: pc,
            gas: gas,
            argumentData: argumentData,
            ctx: ctx
        )
    }
}
