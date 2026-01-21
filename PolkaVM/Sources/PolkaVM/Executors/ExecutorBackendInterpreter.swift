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

            // Calculate gas used
            let postGas = state.getGas()
            let gasUsed = postGas >= GasInt(0) ? gas - Gas(postGas) : gas

            // Get output data from state (only on halt, following invokePVM pattern)
            let outputData: Data?
            switch exitReason {
            case .halt:
                let (addr, len): (UInt32, UInt32) = state.readRegister(Registers.Index(raw: 7), Registers.Index(raw: 8))
                outputData = try? state.readMemory(address: addr, length: Int(len))
            default:
                outputData = nil
            }

            return VMExecutionResult(exitReason: exitReason, gasUsed: gasUsed, outputData: outputData)
        } catch {
            logger.error("Execution failed with error: \(error)")
            return VMExecutionResult(exitReason: .panic(.trap), gasUsed: gas, outputData: nil)
        }
    }
}
