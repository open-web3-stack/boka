import Foundation
import Testing
import Utils

import TracingUtils

@testable import JAMTests
@testable import PolkaVM

private let logger = Logger(label: "PVMMultiModeTests")

/// Multi-mode PVM tests that run in both interpreter and sandbox modes
///
/// These tests use program blobs (standard programs) which can be executed
/// in both interpreter and sandbox modes.
struct PVMMultiModeTests {
    // MARK: - Simple Arithmetic Tests

    /// Test a simple program that adds two numbers
    ///
    /// This test uses the sumToN program which is already available in InvokePVMTest
    /// and can run in both modes.
    @Test func testSumToN_interpreter() async throws {
        try await testSumToN(mode: .interpreter)
    }

    @Test func testSumToN_sandbox() async throws {
        try await testSumToN(mode: .sandbox)
    }

    private func testSumToN(mode: PVMExecutionMode) async throws {
        let sumToN = Data([
            0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 46, 0, 0, 0, 0, 0, 38, 128, 119, 0,
            51, 8, 0, 100, 121, 40, 3, 0, 200, 137, 8, 149, 153, 255, 86, 9, 250,
            61, 8, 0, 0, 2, 0, 51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 77, 18,
            36, 24,
        ])

        let config = DefaultPvmConfig()

        // Test with input = 5, expected output = 15 (1+2+3+4+5)
        let (exitReason, _, output) = await invokePVM(
            config: config,
            executionMode: mode.executionMode,
            blob: sumToN,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data([5]),
            ctx: nil
        )

        let value = output?.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } ?? 0

        switch exitReason {
        case .halt:
            #expect(value == 15, "Expected sum(5) = 15, got \(value)")
        default:
            Issue.record("Expected halt, got \(exitReason) for mode \(mode.description)")
        }
    }

    // MARK: - Fibonacci Tests

    @Test func testFibonacci_interpreter() async throws {
        try await testFibonacci(mode: .interpreter)
    }

    @Test func testFibonacci_sandbox() async throws {
        try await testFibonacci(mode: .sandbox)
    }

    private func testFibonacci(mode: PVMExecutionMode) async throws {
        let fibonacci = Data([
            0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 61, 0, 0, 0, 0, 0, 51, 128, 119, 0,
            51, 8, 1, 51, 9, 1, 40, 3, 0, 149, 119, 255, 81, 7, 12, 100, 138, 200,
            152, 8, 100, 169, 40, 243, 100, 135, 51, 8, 51, 9, 61, 7, 0, 0, 2, 0,
            51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 154, 148, 170, 130, 4, 3,
        ])

        let config = DefaultPvmConfig()

        // Test fib(8) = 34
        let (exitReason, _, output) = await invokePVM(
            config: config,
            executionMode: mode.executionMode,
            blob: fibonacci,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data([8]),
            ctx: nil
        )

        let value = output?.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } ?? 0

        switch exitReason {
        case .halt:
            #expect(value == 34, "Expected fib(8) = 34, got \(value)")
        default:
            Issue.record("Expected halt, got \(exitReason) for mode \(mode.description)")
        }
    }

    // MARK: - Empty Program Tests

    @Test func testEmptyProgram_interpreter() async throws {
        try await testEmptyProgram(mode: .interpreter)
    }

    @Test func testEmptyProgram_sandbox() async throws {
        try await testEmptyProgram(mode: .sandbox)
    }

    private func testEmptyProgram(mode: PVMExecutionMode) async throws {
        let empty = Data([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0])

        let config = DefaultPvmConfig()

        let (exitReason, _, output) = await invokePVM(
            config: config,
            executionMode: mode.executionMode,
            blob: empty,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data(),
            ctx: nil
        )

        #expect(exitReason == .panic(.trap), "Expected panic for empty program in \(mode.description) mode")
        #expect(output == nil, "Expected no output for empty program")
    }

    // MARK: - Gas Consumption Parity Tests

    /// Verify that gas consumption is consistent between modes
    @Test func testGasParity_sumToN() async throws {
        let sumToN = Data([
            0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 46, 0, 0, 0, 0, 0, 38, 128, 119, 0,
            51, 8, 0, 100, 121, 40, 3, 0, 200, 137, 8, 149, 153, 255, 86, 9, 250,
            61, 8, 0, 0, 2, 0, 51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 77, 18,
            36, 24,
        ])

        let config = DefaultPvmConfig()
        let inputGas = Gas(1_000_000)

        // Run in interpreter mode
        let (_, gasUsedInterpreter, _) = await invokePVM(
            config: config,
            executionMode: [], // Empty = interpreter
            blob: sumToN,
            pc: 0,
            gas: inputGas,
            argumentData: Data([5]),
            ctx: nil
        )

        // Run in sandbox mode
        let (_, gasUsedSandbox, _) = await invokePVM(
            config: config,
            executionMode: .sandboxed,
            blob: sumToN,
            pc: 0,
            gas: inputGas,
            argumentData: Data([5]),
            ctx: nil
        )

        // Gas consumption should be similar (allow small differences for mode overhead)
        let gasDiff = abs(Int64(gasUsedInterpreter.value) - Int64(gasUsedSandbox.value))
        #expect(
            gasDiff <= 10,
            "Gas consumption differs significantly between modes: interpreter=\(gasUsedInterpreter), sandbox=\(gasUsedSandbox), diff=\(gasDiff)"
        )
    }

    // MARK: - Output Parity Tests

    /// Verify that program output is identical between modes
    @Test func testOutputParity_fibonacci() async throws {
        let fibonacci = Data([
            0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 61, 0, 0, 0, 0, 0, 51, 128, 119, 0,
            51, 8, 1, 51, 9, 1, 40, 3, 0, 149, 119, 255, 81, 7, 12, 100, 138, 200,
            152, 8, 100, 169, 40, 243, 100, 135, 51, 8, 51, 9, 61, 7, 0, 0, 2, 0,
            51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 154, 148, 170, 130, 4, 3,
        ])

        let config = DefaultPvmConfig()
        let input: UInt8 = 9

        // Run in interpreter mode
        let (_, _, outputInterpreter) = await invokePVM(
            config: config,
            executionMode: [], // Empty = interpreter
            blob: fibonacci,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data([input]),
            ctx: nil
        )

        // Run in sandbox mode
        let (_, _, outputSandbox) = await invokePVM(
            config: config,
            executionMode: .sandboxed,
            blob: fibonacci,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data([input]),
            ctx: nil
        )

        // Outputs should be identical
        #expect(
            outputInterpreter == outputSandbox,
            "Output differs between modes: interpreter=\(outputInterpreter?.toHexString() ?? "nil"), sandbox=\(outputSandbox?.toHexString() ?? "nil")"
        )
    }
}
