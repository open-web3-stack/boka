import Foundation
import TracingUtils
import Utils

final class ExecutorFrontendInProcess: ExecutorFrontend {
    private let logger = Logger(label: "ExecutorFrontendInProcess")
    private let mode: ExecutionMode
    private let backend: ExecutorBackend

    init(mode: ExecutionMode) {
        self.mode = mode

        backend = if mode.contains(.jit) {
            ExecutorBackendJIT()
        } else {
            ExecutorBackendInterpreter()
        }
    }

    func execute(
        config: PvmConfig,
        blob: Data,
        pc: UInt32,
        gas: Gas,
        argumentData: Data?,
        ctx: (any InvocationContext)?
    ) async -> ExitReason {
        await backend.execute(
            config: config,
            blob: blob,
            pc: pc,
            gas: gas,
            argumentData: argumentData,
            ctx: ctx
        )
    }
}
