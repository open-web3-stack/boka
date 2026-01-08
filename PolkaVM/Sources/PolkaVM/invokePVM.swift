import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "InvokePVM")

/// common PVM program-argument invocation function
public func invokePVM(
    config: PvmConfig,
    blob: Data,
    pc: UInt32,
    gas: Gas,
    argumentData: Data?,
    ctx: (any InvocationContext)?
) async -> (ExitReason, Gas, Data?) {
    do {
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
    } catch let e as StandardProgram.Error {
        logger.error("standard program initialization failed: \(e)")
        return (.panic(.trap), Gas(0), nil)
    } catch let e {
        logger.error("unknown error: \(e)")
        return (.panic(.trap), Gas(0), nil)
    }
}
