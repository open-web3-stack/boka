import Foundation
import TracingUtils
import Utils
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

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
        // TODO: spawn a child process, setup IPC channel, and execute the blob in child process
        fatalError("unimplemented")
    }
}
