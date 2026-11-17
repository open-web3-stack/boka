import Foundation
@testable import PolkaVM
import Testing
import Utils

struct ProgramTests {
    @Test func fallingPastCodeDoesNotChargeAnotherBlock() async throws {
        let program = try ProgramCode(Data([0, 0, 1, 1, 1])) // fallthrough
        let state = try VMStateInterpreter(
            program: program, pc: 0, registers: Registers(),
            gas: program.getBlockGasCosts(pc: 0),
            memory: GeneralMemory(pageMap: [], chunks: []),
        )
        let result = await Engine(config: DefaultPvmConfig()).execute(state: state)
        #expect(result == .panic(.invalidBranch))
        #expect(state.getGas() == GasInt(0))
    }

    @Test func invocationValidation() throws {
        // load_imm r0, 1; trap. Only offsets 0 and 3 start instructions.
        let program = try ProgramCode(Data([0, 0, 4, 51, 0, 1, 0, 9]))
        try program.validate(pc: 0)
        try program.validate(pc: 3)
        try ProgramCode(copying: program).validate(pc: 3)
        for pc: UInt32 in [1, 4, .max] {
            #expect(throws: ProgramCode.Error.invalidInstruction) { try program.validate(pc: pc) }
        }
        let invalidPrograms: [Data] = [
            Data([0, 0, 0]), // Empty instruction sequence.
            Data([0, 0, 1, 0, 0]), // Missing initial instruction-start bit.
            Data([0, 0, 2, 2, 0, 1]), // Final instruction is not a terminator.
            Data([0, 0, 3, 0, 255, 0, 7]), // Invalid opcode after a valid entry point.
        ]
        for blob in invalidPrograms {
            let invalid = try ProgramCode(blob)
            #expect(throws: ProgramCode.Error.invalidInstruction) { try invalid.validate(pc: 0) }
            #expect(throws: ProgramCode.Error.invalidInstruction) { try ProgramCode(copying: invalid).validate(pc: 0) }
        }
    }

    @Test func empty() {
        let blob = Data()
        #expect(throws: ProgramCode.Error.invalidJumpTableEntriesCount) { try ProgramCode(blob) }
    }

    @Test func invalidJumpTableEntriesCount() {
        let highValue = Data(UInt64(0x1000001).encode(method: .variableWidth))
        let data = highValue + Data([0, 0])
        #expect(throws: ProgramCode.Error.invalidJumpTableEntriesCount) { try ProgramCode(data) }
    }

    @Test func invalidJumpTableEncodeSize() {
        let data = Data([1, 0xFF, 0, 0])
        #expect(throws: ProgramCode.Error.invalidJumpTableEncodeSize) { try ProgramCode(data) }
    }

    @Test func invalidCodeLength() {
        let highValue = Data(UInt64(0x2000001).encode(method: .variableWidth))
        let data = Data([0, 0]) + highValue
        #expect(throws: ProgramCode.Error.invalidCodeLength) { try ProgramCode(data) }
    }

    @Test func tooMuchData() throws {
        let data = Data([0, 0, 2, 1, 2, 0, 0])
        #expect(throws: ProgramCode.Error.invalidDataLength) { try ProgramCode(data) }
    }

    @Test func tooLittleData() throws {
        let data = Data([0, 0, 2, 1, 2])
        #expect(throws: ProgramCode.Error.invalidDataLength) { try ProgramCode(data) }
    }

    @Test func minimal() throws {
        let data = Data([0, 0, 0])
        _ = try ProgramCode(data)
    }

    @Test func simple() throws {
        let data = Data([0, 0, 2, 1, 2, 0])
        _ = try ProgramCode(data)
    }

    @Test(arguments: [
        (Data(), 0, 0),
        (Data([0]), 0, 7),
        (Data([0]), 8, 0),
        (Data([0b0010_0000]), 0, 4),
        (Data([0b0010_0000]), 3, 1),
        (Data([0b0010_0000]), 6, 1),
        (Data([0b0010_0000]), 7, 0),
        (Data([0, 0, 0b0010_0000, 0b0000_0010]), 0, 20),
        (Data([0, 0, 0b0010_0000, 0b0000_0010]), 2, 18),
        (Data([0, 0, 0b0010_0000, 0b0000_0010]), 10, 10),
        (Data([0, 0, 0b0010_0000, 0b0000_0010]), 22, 2),
        (Data([0, 0, 0, 0b0000_0010]), 5, 19),
    ] as [(Data, UInt32, UInt32)])
    func skip(testCase: (Data, UInt32, UInt32)) {
        #expect(ProgramCode.skip(start: testCase.1, bitmask: testCase.0) == testCase.2)
    }

    @Test(arguments: [
        // inst_branch_eq_imm_nok
        Data([0, 0, 16, 51, 7, 210, 4, 81, 39, 211, 4, 6, 0, 51, 7, 239, 190, 173, 222, 17, 6]),
        // inst_branch_greater_unsigned_imm_ok
        Data([0, 0, 14, 51, 7, 246, 86, 23, 10, 5, 0, 51, 7, 239, 190, 173, 222, 137, 1]),
        // fibonacci general program (from pvm debuger example)
        Data([
            0, 0, 33, 51, 8, 1, 51, 9, 1, 40, 3, 0, 149, 119, 255, 81, 7, 12, 100, 138,
            200, 152, 8, 100, 169, 40, 243, 100, 135, 51, 8, 51, 9, 1, 50, 0, 73, 147, 82, 213, 0,
        ])
    ])
    func parseProgramCode(testCase: Data) throws {
        let program = try ProgramCode(testCase)
        #expect(program.jumpTableEntrySize == 0)
        #expect(program.jumpTable == Data())
        #expect(program.code == testCase[3 ..< testCase[2] + 3])
    }
}
