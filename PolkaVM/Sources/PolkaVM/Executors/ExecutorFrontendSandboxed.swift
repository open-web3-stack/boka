import Foundation
import TracingUtils
import Utils

final class ExecutorFrontendSandboxed: ExecutorFrontend {
    private let logger = Logger(label: "ExecutorFrontendSandboxed")
    private let mode: ExecutionMode

    init(mode: ExecutionMode) {
        self.mode = mode
    }

    func execute(
        config _: PvmConfig,
        blob _: Data,
        pc _: UInt32,
        gas _: Gas,
        argumentData _: Data?,
        ctx _: (any InvocationContext)?
    ) async -> ExitReason {
        fatalError("unimplemented")
    }
}
