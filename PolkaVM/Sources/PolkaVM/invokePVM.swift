import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "InvokePVM")

/// common PVM program-argument invocation function
public func invokePVM(
    config: PvmConfig,
    executionMode: ExecutionMode = [],
    blob: Data,
    pc: UInt32,
    gas: Gas,
    argumentData: Data?,
    ctx: (any InvocationContext)?
) async -> (ExitReason, Gas, Data?) {
    do {
        // Use JIT/Executor if requested, otherwise use Engine (interpreter)
        if executionMode.contains(.jit) {
            let executor = Executor(mode: executionMode, config: config)
            let result = await executor.execute(
                blob: blob,
                pc: pc,
                gas: gas,
                argumentData: argumentData,
                ctx: ctx
            )

            // Handle JIT fallback to interpreter
            if case .fallback = result.exitReason,
               let fallbackState = result.fallbackState {
                logger.debug("JIT falling back to interpreter at PC: \(fallbackState.pc)")

                // Create new interpreter state with JIT state
                let interpreterState = try VMStateInterpreter(
                    standardProgramBlob: blob,
                    pc: fallbackState.pc,
                    gas: Gas(fallbackState.gasUsed),
                    argumentData: argumentData
                )

                // Copy JIT memory to interpreter using writeMemory
                if let jitMemory = result.outputData {
                    // Write memory in chunks to avoid potential issues with large writes
                    let chunkSize = 4096
                    var offset = 0
                    while offset < jitMemory.count {
                        let end = min(offset + chunkSize, jitMemory.count)
                        let chunk = jitMemory[offset..<end]
                        try? interpreterState.writeMemory(address: UInt32(offset), values: chunk)
                        offset = end
                    }
                }

                // Restore JIT registers using writeRegister
                for (index, value) in fallbackState.registers.enumerated() {
                    let regIndex = Registers.Index(raw: UInt8(truncatingIfNeeded: index))
                    interpreterState.writeRegister(regIndex, value)
                }

                // Execute remaining bytecode with interpreter
                let engine = Engine(config: config, invocationContext: ctx)
                let interpreterExitReason = await engine.execute(state: interpreterState)

                let postGas = interpreterState.getGas()
                let interpreterGasUsed = postGas >= GasInt(0) ? Gas(fallbackState.gasUsed) - Gas(postGas) : Gas(fallbackState.gasUsed)

                // Calculate total gas used
                let totalGasUsed = result.gasUsed + interpreterGasUsed

                // Return interpreter result
                switch interpreterExitReason {
                case .outOfGas:
                    return (.outOfGas, totalGasUsed, nil)
                case .halt:
                    let (addr, len): (UInt32, UInt32) = interpreterState.readRegister(Registers.Index(raw: 7), Registers.Index(raw: 8))
                    let output = try? interpreterState.readMemory(address: addr, length: Int(len))
                    return (.halt, totalGasUsed, output ?? Data())
                default:
                    return (.panic(.trap), totalGasUsed, nil)
                }
            }

            return (result.exitReason, result.gasUsed, result.outputData)
        } else {
            let state = try VMStateInterpreter(standardProgramBlob: blob, pc: pc, gas: gas, argumentData: argumentData)
            let engine = Engine(config: config, invocationContext: ctx)
            let exitReason = await engine.execute(state: state)

            let postGas = state.getGas()
            let gasUsed = postGas >= GasInt(0) ? gas - Gas(postGas) : gas

            switch exitReason {
            case .outOfGas:
                return (.outOfGas, gasUsed, nil)
            case .halt:
                let (addr, len): (UInt32, UInt32) = state.readRegister(Registers.Index(raw: 7), Registers.Index(raw: 8))
                let output = try? state.readMemory(address: addr, length: Int(len))
                return (.halt, gasUsed, output ?? Data())
            default:
                return (.panic(.trap), gasUsed, nil)
            }
        }
    } catch let e as StandardProgram.Error {
        logger.error("standard program initialization failed: \(e)")
        return (.panic(.trap), Gas(0), nil)
    } catch let e {
        logger.error("unknown error: \(e)")
        return (.panic(.trap), Gas(0), nil)
    }
}
