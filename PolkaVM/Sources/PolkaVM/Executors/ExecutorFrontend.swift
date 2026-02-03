import Foundation
import Utils

protocol ExecutorFrontend {
    init(mode: ExecutionMode)

    func execute(
        config: PvmConfig,
        blob: Data,
        pc: UInt32,
        gas: Gas,
        argumentData: Data?,
        ctx: (any InvocationContext)?,
    ) async -> VMExecutionResult
}
