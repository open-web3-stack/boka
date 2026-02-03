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
    ) async -> VMExecutionResult {
        do {
            let state = try VMStateInterpreter(standardProgramBlob: blob, pc: pc, gas: gas, argumentData: argumentData)
            let engine = Engine(config: config, invocationContext: ctx)
            let exitReason = await engine.execute(state: state)
            let gasUsed = gas - Gas(state.getGas())
            return VMExecutionResult(
                exitReason: exitReason,
                gasUsed: gasUsed,
                outputData: nil,
                finalRegisters: state.getRegisters(),
                finalPC: state.pc
            )
        } catch {
            logger.error("Execution failed with error: \(error)")
            return VMExecutionResult(
                exitReason: .panic(.trap),
                gasUsed: gas,
                outputData: nil
            )
        }
    }
}
