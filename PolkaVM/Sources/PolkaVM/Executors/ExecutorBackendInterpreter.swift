import Foundation
import TracingUtils
import Utils

final class ExecutorBackendInterpreter: ExecutorBackend {
    private let logger = Logger(label: "ExecutorBackendInterpreter")

    func execute(
        config: PvmConfig,
        blob: Data,
        pc: UInt32,
        gas: Gas,
        argumentData: Data?,
        ctx: (any InvocationContext)?
    ) async -> ExitReason {
        do {
            let state = try VMState(standardProgramBlob: blob, pc: pc, gas: gas, argumentData: argumentData)
            let engine = Engine(config: config, invocationContext: ctx)
            return await engine.execute(state: state)
        } catch {
            logger.error("Execution failed with error: \(error)")
            return .panic(.trap)
        }
    }
}
