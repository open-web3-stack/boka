import Foundation
import PolkaVM
import Utils

/// Export a wasm file for using in https://pvm.fluffylabs.dev/ debugger
/// see <https://github.com/FluffyLabs/pvm-debugger/issues/81> for more details

private class PVM {
    public let engine: Engine
    public let vmState: VMState

    init(program: Data, registers: Data, gas: Int64) throws {
        let program = try ProgramCode(program)
        let registers = try Registers(data: registers)
        let memory = Memory(
            pageMap: [],
            chunks: []
        )
        vmState = VMState(program: program, pc: 0, registers: registers, gas: Gas(UInt64(gas)), memory: memory)
        engine = Engine(config: DefaultPvmConfig())
    }
}

private enum Status: UInt8 {
    case ok = 0
    case halt = 1
    case panic = 2
    case outOfGas = 3
    case hostCall = 4
    case pageFault = 5
}

private var PVMInstance: PVM?
private var PVMStatus: Status = .halt

@MainActor private func withPvm<R>(f: (inout PVM) -> R, defaultVal: R) -> R {
    if var pvm = PVMInstance {
        return f(&pvm)
    }
    return defaultVal
}

@_expose(wasm, "reset")
// @_cdecl("reset")
@MainActor public func reset(program: Data, registers: Data, gas: Int64) throws {
    PVMInstance = try PVM(program: program, registers: registers, gas: gas)
}

@_expose(wasm, "nextStep")
// @_cdecl("nextStep")
@MainActor public func nextStep() throws -> Bool {
    withPvm(f: { pvm in
        let context = ExecutionContext(state: pvm.vmState, config: DefaultPvmConfig())
        let exitReason = pvm.engine.step(program: pvm.vmState.program, context: context)

        switch exitReason {
        case .continued:
            return true
        case let .exit(exitReason):
            PVMStatus = switch exitReason {
            case .halt:
                .halt
            case .panic:
                .panic
            case .outOfGas:
                .outOfGas
            case .hostCall:
                .hostCall
            case .pageFault:
                .pageFault
            }
            return false
        }
    }, defaultVal: false)
}

@_expose(wasm, "getProgramCounter")
// @_cdecl("getProgramCounter")
@MainActor public func getProgramCounter() throws -> UInt32 {
    withPvm(f: { pvm in
        pvm.vmState.pc
    }, defaultVal: 0)
}

@_expose(wasm, "getStatus")
// @_cdecl("getStatus")
@MainActor public func getStatus() throws -> UInt8 {
    withPvm(f: { _ in
        PVMStatus.rawValue
    }, defaultVal: 0)
}

@_expose(wasm, "getGasLeft")
// @_cdecl("getGasLeft")
@MainActor public func getGasLeft() throws -> Int64 {
    withPvm(f: { pvm in
        pvm.vmState.getGas().value
    }, defaultVal: 0)
}

@_expose(wasm, "getRegisters")
// @_cdecl("getRegisters")
@MainActor public func getRegisters() throws -> Data {
    withPvm(f: { pvm in
        var values: [UInt32] = []
        for i in 0 ..< 13 {
            let value = pvm.vmState.getRegisters()[Registers.Index(raw: UInt8(i))]
            values.append(value)
        }
        return values.withUnsafeBufferPointer {
            Data(buffer: $0)
        }
    }, defaultVal: Data())
}

@_expose(wasm, "getPageDump")
// @_cdecl("getPageDump")
@MainActor public func getPageDump(pageIndex _: UInt32) throws -> Data {
    withPvm(f: { _ in
        // TODO: implement after debugger support this
        Data()
    }, defaultVal: Data())
}
