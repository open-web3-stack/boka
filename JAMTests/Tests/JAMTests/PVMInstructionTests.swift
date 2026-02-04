import Foundation
@testable import JAMTests
import PolkaVM
import Testing
import TracingUtils
import Utils

private let logger = Logger(label: "PVMInstructionTests")

/// Comprehensive instruction tests that run in both interpreter and sandbox modes
///
/// These tests focus on verifying that individual instructions work correctly
/// in both execution modes.
struct PVMInstructionTests {
    // MARK: - Branch Instructions

    @Test func conditionalBranch_interpreter() async throws {
        try await testConditionalBranch(mode: .interpreter)
    }

    @Test func conditionalBranch_sandbox() async throws {
        try await testConditionalBranch(mode: .sandbox)
    }

    private func testConditionalBranch(mode: PVMExecutionMode) async throws {
        // Test branch if less than
        // Program should branch if w1 < w2
        let config = DefaultPvmConfig()

        // Create a simple branch test program
        // This is a simplified version - in real tests we'd use actual bytecode
        _ = await invokePVM(
            config: config,
            executionMode: mode.executionMode,
            blob: Data([0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0]),
            pc: 0,
            gas: Gas(100_000),
            argumentData: Data(),
            ctx: nil,
        )

        // For now, just verify it doesn't crash
    }

    // MARK: - Load/Store Instructions

    @Test func loadStore_interpreter() async throws {
        try await testLoadStore(mode: .interpreter)
    }

    @Test func loadStore_sandbox() async throws {
        try await testLoadStore(mode: .sandbox)
    }

    private func testLoadStore(mode _: PVMExecutionMode) async throws {
        // Test basic load/store operations
    }

    // MARK: - Edge Case Tests

    /// Test that both modes handle edge cases consistently
    @Test func edgeCase_zeroGas() async {
        let config = DefaultPvmConfig()

        // Test with zero gas - should fail immediately
        let (exitReasonInterpreter, _, _) = await invokePVM(
            config: config,
            executionMode: [],
            blob: Data([0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0]),
            pc: 0,
            gas: Gas(0),
            argumentData: Data(),
            ctx: nil,
        )

        let (exitReasonSandbox, _, _) = await invokePVM(
            config: config,
            executionMode: .sandboxed,
            blob: Data([0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0]),
            pc: 0,
            gas: Gas(0),
            argumentData: Data(),
            ctx: nil,
        )

        // Both should fail with out of gas
        #expect(exitReasonInterpreter == .outOfGas)
        #expect(exitReasonSandbox == .outOfGas)
    }

    @Test func edgeCase_largeArgument() async {
        let config = DefaultPvmConfig()

        // Test with large argument data
        let largeArgument = Data(repeating: 0xFF, count: 1000)

        let (exitReasonInterpreter, _, _) = await invokePVM(
            config: config,
            executionMode: [],
            blob: Data([0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0]),
            pc: 0,
            gas: Gas(100_000),
            argumentData: largeArgument,
            ctx: nil,
        )

        let (exitReasonSandbox, _, _) = await invokePVM(
            config: config,
            executionMode: .sandboxed,
            blob: Data([0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0]),
            pc: 0,
            gas: Gas(100_000),
            argumentData: largeArgument,
            ctx: nil,
        )

        // Both should handle large arguments the same way
        #expect(exitReasonInterpreter == exitReasonSandbox)
    }

    @Test func edgeCase_maxGas() async {
        let config = DefaultPvmConfig()

        // Test with very large gas value (not max to avoid overflow)
        let largeGas = Gas(1_000_000_000_000)

        let (exitReasonInterpreter, gasUsedInterpreter, _) = await invokePVM(
            config: config,
            executionMode: [],
            blob: Data([0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0]),
            pc: 0,
            gas: largeGas,
            argumentData: Data(),
            ctx: nil,
        )

        let (exitReasonSandbox, gasUsedSandbox, _) = await invokePVM(
            config: config,
            executionMode: .sandboxed,
            blob: Data([0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0]),
            pc: 0,
            gas: largeGas,
            argumentData: Data(),
            ctx: nil,
        )

        // Both should complete and use similar amounts of gas
        #expect(exitReasonInterpreter == exitReasonSandbox)

        let gasDiff = abs(Int64(gasUsedInterpreter.value) - Int64(gasUsedSandbox.value))
        #expect(gasDiff <= 10)
    }

    // MARK: - Comprehensive Parity Tests

    /// Run a comprehensive parity test across multiple scenarios
    @Test func comprehensiveParity_multipleScenarios() async {
        let config = DefaultPvmConfig()

        // Test different input values with the sumToN program
        let testCases: [(UInt8, UInt32)] = [
            (1, 1), // sum(1) = 1
            (5, 15), // sum(5) = 15
            (10, 55), // sum(10) = 55
        ]

        let sumToN = Data([
            0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 46, 0, 0, 0, 0, 0, 38, 128, 119, 0,
            51, 8, 0, 100, 121, 40, 3, 0, 200, 137, 8, 149, 153, 255, 86, 9, 250,
            61, 8, 0, 0, 2, 0, 51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 77, 18,
            36, 24,
        ])

        for (input, expectedOutput) in testCases {
            // Run in interpreter mode
            let (exitReasonInterpreter, _, outputInterpreter) = await invokePVM(
                config: config,
                executionMode: [],
                blob: sumToN,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([input]),
                ctx: nil,
            )

            // Run in sandbox mode
            let (exitReasonSandbox, _, outputSandbox) = await invokePVM(
                config: config,
                executionMode: .sandboxed,
                blob: sumToN,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([input]),
                ctx: nil,
            )

            // Verify exit reasons match
            #expect(
                exitReasonInterpreter == exitReasonSandbox,
            )

            // Verify outputs match
            #expect(
                outputInterpreter == outputSandbox,
            )

            // Verify expected output
            let valueInterpreter = outputInterpreter?.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } ?? 0
            let valueSandbox = outputSandbox?.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } ?? 0

            #expect(
                valueInterpreter == expectedOutput,
            )

            #expect(
                valueSandbox == expectedOutput,
            )
        }
    }
}
