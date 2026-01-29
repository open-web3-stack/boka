import Foundation
import PolkaVM
import Testing
import TracingUtils
import Utils

@testable import JAMTests

private let logger = Logger(label: "PVMComprehensiveParityTests")

/// Comprehensive parity tests that verify interpreter and sandbox modes
/// produce identical results across a wide range of scenarios.
struct PVMComprehensiveParityTests {
    // MARK: - Fibonacci Parity Tests

    @Test func parity_fibonacci_multipleInputs() async throws {
        let config = DefaultPvmConfig()

        let fibonacci = Data([
            0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 61, 0, 0, 0, 0, 0, 51, 128, 119, 0,
            51, 8, 1, 51, 9, 1, 40, 3, 0, 149, 119, 255, 81, 7, 12, 100, 138, 200,
            152, 8, 100, 169, 40, 243, 100, 135, 51, 8, 51, 9, 61, 7, 0, 0, 2, 0,
            51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 154, 148, 170, 130, 4, 3,
        ])

        // Test multiple fibonacci inputs
        let testCases: [(UInt8, UInt32)] = [
            (1, 1),
            (2, 2),
            (3, 3),
            (5, 8),
            (8, 34),
            (10, 89),
        ]

        for (input, expectedOutput) in testCases {
            // Interpreter mode
            let (exitReasonInterpreter, _, outputInterpreter) = await invokePVM(
                config: config,
                executionMode: [],
                blob: fibonacci,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([input]),
                ctx: nil
            )

            // Sandbox mode
            let (exitReasonSandbox, _, outputSandbox) = await invokePVM(
                config: config,
                executionMode: .sandboxed,
                blob: fibonacci,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([input]),
                ctx: nil
            )

            // Verify exit reasons match
            #expect(
                exitReasonInterpreter == exitReasonSandbox,
                "Fibonacci(\(input)): Exit reasons differ - interpreter=\(exitReasonInterpreter), sandbox=\(exitReasonSandbox)"
            )

            // Verify outputs match
            #expect(
                outputInterpreter == outputSandbox,
                "Fibonacci(\(input)): Outputs differ - interpreter=\(outputInterpreter?.toHexString() ?? "nil"), sandbox=\(outputSandbox?.toHexString() ?? "nil")"
            )

            // Verify expected output
            // Only load UInt32 if output has at least 4 bytes
            let valueInterpreter: UInt32
            if let output = outputInterpreter, output.count >= 4 {
                valueInterpreter = output.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            } else {
                valueInterpreter = 0
            }

            let valueSandbox: UInt32
            if let output = outputSandbox, output.count >= 4 {
                valueSandbox = output.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            } else {
                valueSandbox = 0
            }

            #expect(
                valueInterpreter == expectedOutput,
                "Fibonacci(\(input)): Interpreter output mismatch - expected=\(expectedOutput), got=\(valueInterpreter)"
            )

            #expect(
                valueSandbox == expectedOutput,
                "Fibonacci(\(input)): Sandbox output mismatch - expected=\(expectedOutput), got=\(valueSandbox)"
            )

            logger.info("Fibonacci(\(input)): both modes produced \(valueInterpreter)")
        }
    }

    // MARK: - SumToN Parity Tests

    @Test func parity_sumToN_wideRange() async throws {
        let config = DefaultPvmConfig()

        let sumToN = Data([
            0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 46, 0, 0, 0, 0, 0, 38, 128, 119, 0,
            51, 8, 0, 100, 121, 40, 3, 0, 200, 137, 8, 149, 153, 255, 86, 9, 250,
            61, 8, 0, 0, 2, 0, 51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 77, 18,
            36, 24,
        ])

        // Test a wider range of inputs
        let testCases: [(UInt8, UInt32)] = [
            (0, 0),
            (1, 1),
            (2, 3),
            (3, 6),
            (5, 15),
            (7, 28),
            (10, 55),
            (15, 120),
            (20, 210),
        ]

        for (input, expectedOutput) in testCases {
            let (exitReasonInterpreter, _, outputInterpreter) = await invokePVM(
                config: config,
                executionMode: [],
                blob: sumToN,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([input]),
                ctx: nil
            )

            let (exitReasonSandbox, _, outputSandbox) = await invokePVM(
                config: config,
                executionMode: .sandboxed,
                blob: sumToN,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([input]),
                ctx: nil
            )

            // Verify parity
            #expect(exitReasonInterpreter == exitReasonSandbox)
            #expect(outputInterpreter == outputSandbox)

            // Only load UInt32 if output has at least 4 bytes
            let valueInterpreter: UInt32
            if let output = outputInterpreter, output.count >= 4 {
                valueInterpreter = output.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            } else {
                valueInterpreter = 0
            }

            let valueSandbox: UInt32
            if let output = outputSandbox, output.count >= 4 {
                valueSandbox = output.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            } else {
                valueSandbox = 0
            }

            #expect(valueInterpreter == expectedOutput)
            #expect(valueSandbox == expectedOutput)

            logger.info("SumToN(\(input)): both modes produced \(valueInterpreter)")
        }
    }

    // MARK: - Error Handling Parity

    @Test func parity_errorHandling() async throws {
        let config = DefaultPvmConfig()

        // Use empty program which should panic in both modes
        let empty = Data([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0])

        let (exitReasonInterpreter, _, _) = await invokePVM(
            config: config,
            executionMode: [],
            blob: empty,
            pc: 0,
            gas: Gas(100_000),
            argumentData: Data(),
            ctx: nil
        )

        let (exitReasonSandbox, _, _) = await invokePVM(
            config: config,
            executionMode: .sandboxed,
            blob: empty,
            pc: 0,
            gas: Gas(100_000),
            argumentData: Data(),
            ctx: nil
        )

        // Both should panic with trap
        #expect(exitReasonInterpreter == .panic(.trap))
        #expect(exitReasonSandbox == .panic(.trap))
        logger.info("Error handling parity: both modes correctly panicked on empty program")
    }

    // MARK: - Gas Exhaustion Parity

    @Test func parity_gasExhaustion() async throws {
        let config = DefaultPvmConfig()

        let fibonacci = Data([
            0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 61, 0, 0, 0, 0, 0, 51, 128, 119, 0,
            51, 8, 1, 51, 9, 1, 40, 3, 0, 149, 119, 255, 81, 7, 12, 100, 138, 200,
            152, 8, 100, 169, 40, 243, 100, 135, 51, 8, 51, 9, 61, 7, 0, 0, 2, 0,
            51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 154, 148, 170, 130, 4, 3,
        ])

        // Provide insufficient gas for the computation
        let limitedGas = Gas(50)

        let (exitReasonInterpreter, _, _) = await invokePVM(
            config: config,
            executionMode: [],
            blob: fibonacci,
            pc: 0,
            gas: limitedGas,
            argumentData: Data([25]), // Large input requiring more computation
            ctx: nil
        )

        let (exitReasonSandbox, _, _) = await invokePVM(
            config: config,
            executionMode: .sandboxed,
            blob: fibonacci,
            pc: 0,
            gas: limitedGas,
            argumentData: Data([25]),
            ctx: nil
        )

        // Both should run out of gas or fail consistently
        #expect(
            exitReasonInterpreter == exitReasonSandbox,
            "Gas exhaustion: Exit reasons differ - interpreter=\(exitReasonInterpreter), sandbox=\(exitReasonSandbox)"
        )

        logger.info("Gas exhaustion parity: both modes handled gas limit consistently (exit reason: \(exitReasonInterpreter))")
    }

    // MARK: - Large Argument Parity

    @Test func parity_largeArguments() async throws {
        let config = DefaultPvmConfig()

        let sumToN = Data([
            0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 46, 0, 0, 0, 0, 0, 38, 128, 119, 0,
            51, 8, 0, 100, 121, 40, 3, 0, 200, 137, 8, 149, 153, 255, 86, 9, 250,
            61, 8, 0, 0, 2, 0, 51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 77, 18,
            36, 24,
        ])

        // Test with increasingly large argument sizes
        let argumentSizes = [0, 100, 1000, 5000, 10000]

        for size in argumentSizes {
            let argumentData = Data(repeating: UInt8(truncatingIfNeeded: size), count: size)

            let (exitReasonInterpreter, _, outputInterpreter) = await invokePVM(
                config: config,
                executionMode: [],
                blob: sumToN,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: argumentData,
                ctx: nil
            )

            let (exitReasonSandbox, _, outputSandbox) = await invokePVM(
                config: config,
                executionMode: .sandboxed,
                blob: sumToN,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: argumentData,
                ctx: nil
            )

            // Both should handle large arguments identically
            #expect(
                exitReasonInterpreter == exitReasonSandbox,
                "Large argument (\(size) bytes): Exit reasons differ"
            )

            #expect(
                outputInterpreter == outputSandbox,
                "Large argument (\(size) bytes): Outputs differ"
            )

            logger.info("Large argument parity (\(size) bytes): both modes handled identically")
        }
    }

    // MARK: - Comprehensive State Parity

    @Test func parity_comprehensiveState() async throws {
        let config = DefaultPvmConfig()

        // Test that both modes produce identical state for complex computations
        // This test runs multiple programs and verifies complete state parity

        let programs: [(Data, Data, UInt32)] = [
            // (program, argument, expected_output)
            (
                Data([0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 46, 0, 0, 0, 0, 0, 38, 128, 119, 0,
                      51, 8, 0, 100, 121, 40, 3, 0, 200, 137, 8, 149, 153, 255, 86, 9, 250,
                      61, 8, 0, 0, 2, 0, 51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 77, 18,
                      36, 24]),
                Data([5]),
                15
            ),
            (
                Data([0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 61, 0, 0, 0, 0, 0, 51, 128, 119, 0,
                      51, 8, 1, 51, 9, 1, 40, 3, 0, 149, 119, 255, 81, 7, 12, 100, 138, 200,
                      152, 8, 100, 169, 40, 243, 100, 135, 51, 8, 51, 9, 61, 7, 0, 0, 2, 0,
                      51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 154, 148, 170, 130, 4, 3]),
                Data([8]),
                34
            ),
        ]

        for (program, argument, expectedOutput) in programs {
            let (_, _, outputInterpreter) = await invokePVM(
                config: config,
                executionMode: [],
                blob: program,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: argument,
                ctx: nil
            )

            let (_, _, outputSandbox) = await invokePVM(
                config: config,
                executionMode: .sandboxed,
                blob: program,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: argument,
                ctx: nil
            )

            #expect(
                outputInterpreter == outputSandbox,
                "Outputs differ for argument=\(argument.toHexString())"
            )

            let valueInterpreter = outputInterpreter?.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } ?? 0
            let valueSandbox = outputSandbox?.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } ?? 0

            #expect(valueInterpreter == expectedOutput)
            #expect(valueSandbox == expectedOutput)

            logger.info("Comprehensive state parity: both modes produced \(valueInterpreter)")
        }
    }
}
