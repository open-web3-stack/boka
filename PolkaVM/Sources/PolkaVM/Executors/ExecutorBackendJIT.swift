import asmjit
import CppHelper
import Foundation
import TracingUtils
import Utils

final class ExecutorBackendJIT: ExecutorBackend {
    private let logger = Logger(label: "JIT")

    func execute(
        config _: PvmConfig,
        blob _: Data,
        pc _: UInt32,
        gas _: Gas,
        argumentData _: Data?,
        ctx _: (any InvocationContext)?
    ) async -> ExitReason {
        fatalError("JIT execution is not implemented yet.")
    }
}
