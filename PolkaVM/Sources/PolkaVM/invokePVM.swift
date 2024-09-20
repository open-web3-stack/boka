import Foundation
import TracingUtils

private let logger = Logger(label: "invokePVM")

/// common PVM program-argument invocation function
public func invokePVM(config: PvmConfig, blob: Data, pc: UInt32, gas: UInt64, argumentData: Data?,
                      ctx: any InvocationContext) -> (ExitReason, VMState?, UInt64?, Data?)
{
    do {
        let state = try VMState(standardProgramBlob: blob, pc: pc, gas: gas, argumentData: argumentData)
        let engine = Engine(config: config, invocationContext: ctx)
        let exitReason = engine.execute(program: state.program, state: state)

        switch exitReason {
        case .outOfGas:
            return (.outOfGas, state, nil, nil)
        case .halt:
            let (reg10, reg11) = state.readRegister(Registers.Index(raw: 10), Registers.Index(raw: 11))
            // TODO: check if this is correct
            let output = try? state.readMemory(address: reg10, length: Int(reg11 - reg10))
            return (.halt, state, UInt64(state.getGas()), output ?? Data())
        default:
            return (.panic(.trap), state, nil, nil)
        }
    } catch let e as StandardProgram.Error {
        logger.error("standard program initialization failed: \(e)")
        return (.panic(.trap), nil, nil, nil)
    } catch let e {
        logger.error("unknown error: \(e)")
        return (.panic(.trap), nil, nil, nil)
    }
}
