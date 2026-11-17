import Foundation
@testable import PolkaVM
import Testing
import Utils

struct ControlFlowValidationTests {
    @Test
    func unlikelyDoesNotSkipTheFollowingInstruction() async throws {
        // unlikely; load_imm r0, 7; trap. The instruction starts are 0, 1 and 7.
        let code = Data([0, 0, 8, 2, 51, 0, 7, 0, 0, 0, 0, 131])
        let program = try ProgramCode(code)
        let result = await JITInstructionExecutor.execute(
            blob: ProgramBlobBuilder.createStandardProgram(programCode: code), gas: Gas(1000),
        )
        #expect(result.exitReason == .panic(.trap))
        #expect(result.finalRegisters[.init(raw: 0)] == 7)
        #expect(result.finalGas == Gas(1000) - program.getBlockGasCosts(pc: 0))
    }

    @Test
    func takenBranchRejectsMissingFallthrough() async throws {
        let code = Data([0, 0, 3, 170, 0, 0, 1])
        let program = try ProgramCode(code)
        let state = try VMStateInterpreter(
            program: program, pc: 0, registers: Registers(), gas: Gas(1000),
            memory: GeneralMemory(pageMap: [], chunks: []),
        )
        let exit = await Engine(config: DefaultPvmConfig()).execute(state: state)
        #expect(exit == .panic(.invalidBranch))
        let result = await JITInstructionExecutor.execute(blob: ProgramBlobBuilder.createStandardProgram(programCode: code))
        #expect(result.exitReason == .panic(.trap))
        #expect(result.finalGas > Gas(0))
    }

    @Test
    func untakenBranchRejectsOperandDestination() async throws {
        let code = Data([0, 0, 7, 171, 0, 1, 51, 2, 9, 0, 73])
        let program = try ProgramCode(code)
        let state = try VMStateInterpreter(
            program: program, pc: 0, registers: Registers(), gas: Gas(1000),
            memory: GeneralMemory(pageMap: [], chunks: []),
        )
        let exit = await Engine(config: DefaultPvmConfig()).execute(state: state)
        #expect(exit == .panic(.invalidBranch))
        #expect(state.readRegister(.init(raw: 2)) as UInt64 == 0)
        #expect(!program.basicBlockIndices.contains(7))

        let result = await JITInstructionExecutor.execute(blob: ProgramBlobBuilder.createStandardProgram(programCode: code))
        #expect(result.exitReason == .panic(.trap))
        #expect(result.finalRegisters[.init(raw: 2)] == 0)
    }

    @Test
    func jitMidBlockEntryChargesOnlyOnEntryAndBackedge() async throws {
        let code = Data([0, 0, 12, 51, 0, 7, 0, 0, 0, 2, 40, 249, 255, 255, 255, 193, 0])
        let program = try ProgramCode(code)
        let cost = program.getBlockGasCosts(pc: 0)
        let blob = ProgramBlobBuilder.createStandardProgram(programCode: code)
        let first = await JITInstructionExecutor.execute(blob: blob, pc: 6, gas: cost)
        #expect(first.exitReason == .outOfGas)
        #expect(first.finalGas == Gas(0))
        // Starting inside the block must skip the initial load.
        #expect(first.finalRegisters[.init(raw: 0)] != 7)
        let repeated = await JITInstructionExecutor.execute(blob: blob, pc: 6, gas: cost * 3)
        #expect(repeated.exitReason == .outOfGas)
        #expect(repeated.finalGas == Gas(0))
        #expect(repeated.finalRegisters[.init(raw: 0)] == 7)
    }
}
