import Foundation
@testable import JAMTests
import PolkaVM
import Testing
import TracingUtils
import Utils

private let logger = Logger(label: "PVMGasAndMemoryTests")

/// Gas and memory behavior tests for both interpreter and sandbox modes
///
/// These tests verify that gas accounting and memory management work correctly
/// and consistently across both execution modes.
struct PVMGasAndMemoryTests {
    // MARK: - Gas Calculation Tests

    @Test func gasCalculation_interpreter() async throws {
        try await testGasCalculation(mode: .interpreter)
    }

    @Test func gasCalculation_sandbox() async throws {
        try await testGasCalculation(mode: .sandbox)
    }

    private func testGasCalculation(mode: PVMExecutionMode) async throws {
        let config = DefaultPvmConfig()
        let initialGas = Gas(100_000)

        // Use a program that does some computation
        let sumToN = Data([
            0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 46, 0, 0, 0, 0, 0, 38, 128, 119, 0,
            51, 8, 0, 100, 121, 40, 3, 0, 200, 137, 8, 149, 153, 255, 86, 9, 250,
            61, 8, 0, 0, 2, 0, 51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 77, 18,
            36, 24,
        ])

        let (exitReason, gasUsed, _) = await invokePVM(
            config: config,
            executionMode: mode.executionMode,
            blob: sumToN,
            pc: 0,
            gas: initialGas,
            argumentData: Data([10]),
            ctx: nil,
        )

        #expect(exitReason == .halt, "Program should complete successfully")
        #expect(gasUsed > Gas(0), "Should consume some gas")
        #expect(gasUsed < initialGas, "Should not consume more than initial gas")

        let remainingGas = initialGas - gasUsed

        // Verify gas is reasonable (not too little, not too much)
        #expect(gasUsed.value > 10, "Should use at least some gas for computation")
        #expect(gasUsed.value < 50000, "Should not use excessive gas")
    }

    @Test func gasExhaustion_interpreter() async throws {
        try await testGasExhaustion(mode: .interpreter)
    }

    @Test func gasExhaustion_sandbox() async throws {
        try await testGasExhaustion(mode: .sandbox)
    }

    private func testGasExhaustion(mode: PVMExecutionMode) async throws {
        let config = DefaultPvmConfig()

        // Use a program that requires more gas than provided
        let fibonacci = Data([
            0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 61, 0, 0, 0, 0, 0, 51, 128, 119, 0,
            51, 8, 1, 51, 9, 1, 40, 3, 0, 149, 119, 255, 81, 7, 12, 100, 138, 200,
            152, 8, 100, 169, 40, 243, 100, 135, 51, 8, 51, 9, 61, 7, 0, 0, 2, 0,
            51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 154, 148, 170, 130, 4, 3,
        ])

        // Provide very limited gas
        let limitedGas = Gas(100)

        let (exitReason, gasUsed, _) = await invokePVM(
            config: config,
            executionMode: mode.executionMode,
            blob: fibonacci,
            pc: 0,
            gas: limitedGas,
            argumentData: Data([20]), // Large input to require more computation
            ctx: nil,
        )

        // Should run out of gas
        #expect(exitReason == .outOfGas, "Should run out of gas with limited budget")
    }

    // MARK: - Memory Boundary Tests

    @Test func memoryBoundaries_interpreter() async throws {
        try await testMemoryBoundaries(mode: .interpreter)
    }

    @Test func memoryBoundaries_sandbox() async throws {
        try await testMemoryBoundaries(mode: .sandbox)
    }

    private func testMemoryBoundaries(mode: PVMExecutionMode) async throws {
        let config = DefaultPvmConfig()

        // Test with various argument sizes
        let argumentSizes = [0, 1, 100, 1000, 10000]

        for size in argumentSizes {
            let argumentData = Data(repeating: UInt8(truncatingIfNeeded: size % 256), count: size)

            let (exitReason, _, _) = await invokePVM(
                config: config,
                executionMode: mode.executionMode,
                blob: Data([0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0]),
                pc: 0,
                gas: Gas(100_000),
                argumentData: argumentData,
                ctx: nil,
            )

            // All should handle arguments without crashing
        }
    }

    // MARK: - Gas Consistency Tests

    /// Verify that gas consumption is consistent across multiple runs
    @Test func gasConsistency_interpreter() async throws {
        try await testGasConsistency(mode: .interpreter)
    }

    @Test func gasConsistency_sandbox() async throws {
        try await testGasConsistency(mode: .sandbox)
    }

    private func testGasConsistency(mode: PVMExecutionMode) async throws {
        let config = DefaultPvmConfig()

        let sumToN = Data([
            0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 46, 0, 0, 0, 0, 0, 38, 128, 119, 0,
            51, 8, 0, 100, 121, 40, 3, 0, 200, 137, 8, 149, 153, 255, 86, 9, 250,
            61, 8, 0, 0, 2, 0, 51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 77, 18,
            36, 24,
        ])

        // Run the same program multiple times
        var gasValues: [UInt64] = []
        for _ in 0 ..< 5 {
            let (_, gasUsed, _) = await invokePVM(
                config: config,
                executionMode: mode.executionMode,
                blob: sumToN,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([10]),
                ctx: nil,
            )
            gasValues.append(gasUsed.value)
        }

        // All gas values should be identical
        let firstGas = gasValues[0]
        for (index, gas) in gasValues.enumerated() {
            #expect(
                gas == firstGas,
                "\(mode.description) gas inconsistent across runs: run 0 used \(firstGas), run \(index) used \(gas)",
            )
        }
    }

    // MARK: - Complex Program Gas Tests

    /// Test gas consumption for programs with different complexity
    @Test func gasVsComplexity() async {
        let config = DefaultPvmConfig()

        // Test programs of different complexities
        let simple = Data([0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0])

        let sumToN = Data([
            0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 46, 0, 0, 0, 0, 0, 38, 128, 119, 0,
            51, 8, 0, 100, 121, 40, 3, 0, 200, 137, 8, 149, 153, 255, 86, 9, 250,
            61, 8, 0, 0, 2, 0, 51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 77, 18,
            36, 24,
        ])

        let fibonacci = Data([
            0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 61, 0, 0, 0, 0, 0, 51, 128, 119, 0,
            51, 8, 1, 51, 9, 1, 40, 3, 0, 149, 119, 255, 81, 7, 12, 100, 138, 200,
            152, 8, 100, 169, 40, 243, 100, 135, 51, 8, 51, 9, 61, 7, 0, 0, 2, 0,
            51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 154, 148, 170, 130, 4, 3,
        ])

        let programs = [
            ("simple", simple),
            ("sumToN", sumToN),
            ("fibonacci", fibonacci),
        ]

        for (name, program) in programs {
            // Test in interpreter mode
            let (_, gasInterpreter, _) = await invokePVM(
                config: config,
                executionMode: [],
                blob: program,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([5]),
                ctx: nil,
            )

            // Test in sandbox mode
            let (_, gasSandbox, _) = await invokePVM(
                config: config,
                executionMode: .sandboxed,
                blob: program,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([5]),
                ctx: nil,
            )

            // Gas should be similar
            let gasDiff = abs(Int64(gasInterpreter.value) - Int64(gasSandbox.value))
            let gasMessage =
                "\(name): Gas consumption differs significantly between modes: " +
                "interpreter=\(gasInterpreter), sandbox=\(gasSandbox), diff=\(gasDiff)"
            #expect(
                gasDiff <= 20,
                gasMessage,
            )
        }
    }

    // MARK: - Stress Tests

    /// Test with programs that push memory boundaries
    @Test func stress_largeOutput() async {
        let config = DefaultPvmConfig()

        // Create a program that tries to write large output
        // For now, use empty program as placeholder
        let (exitReasonInterpreter, _, _) = await invokePVM(
            config: config,
            executionMode: [],
            blob: Data([0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0]),
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data(),
            ctx: nil,
        )

        let (exitReasonSandbox, _, _) = await invokePVM(
            config: config,
            executionMode: .sandboxed,
            blob: Data([0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0]),
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data(),
            ctx: nil,
        )

        // Both should handle the stress case similarly
        #expect(exitReasonInterpreter == exitReasonSandbox)
    }
}
