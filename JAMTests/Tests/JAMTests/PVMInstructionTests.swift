import Foundation
@testable import JAMTests
import PolkaVM
import Testing
import Utils

/// PVM interpreter instruction and edge-case smoke tests.
struct PVMInstructionTests {
    @Test func conditionalBranch_interpreter() async throws {
        _ = await invokePVM(
            config: DefaultPvmConfig(),
            executionMode: [],
            blob: Data([0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0]),
            pc: 0,
            gas: Gas(100_000),
            argumentData: Data(),
            ctx: nil,
        )
    }

    @Test func loadStore_interpreter() async throws {
        // Placeholder for low-level load/store vectors.
    }

    @Test func edgeCase_zeroGas() async {
        let (exitReason, _, _) = await invokePVM(
            config: DefaultPvmConfig(),
            executionMode: [],
            blob: Data([0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0]),
            pc: 0,
            gas: Gas(0),
            argumentData: Data(),
            ctx: nil,
        )

        #expect(exitReason == .outOfGas)
    }

    @Test func edgeCase_largeArgument() async {
        _ = await invokePVM(
            config: DefaultPvmConfig(),
            executionMode: [],
            blob: Data([0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0]),
            pc: 0,
            gas: Gas(100_000),
            argumentData: Data(repeating: 0xFF, count: 1000),
            ctx: nil,
        )
    }

    @Test func edgeCase_maxGas() async {
        _ = await invokePVM(
            config: DefaultPvmConfig(),
            executionMode: [],
            blob: Data([0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0]),
            pc: 0,
            gas: Gas(1_000_000_000_000),
            argumentData: Data(),
            ctx: nil,
        )
    }
}
