import Foundation
import PolkaVM
import Testing
import TracingUtils
import Utils

@testable import JAMTests

private let logger = Logger(label: "PVMStressTests")

/// Stress tests that push the boundaries of both interpreter and sandbox modes
///
/// These tests verify that both modes handle extreme cases correctly.
struct PVMStressTests {
    // MARK: - Extreme Gas Values

    @Test func stress_extremeGasValues() async throws {
        let config = DefaultPvmConfig()

        let fibonacci = Data([
            0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 61, 0, 0, 0, 0, 0, 51, 128, 119, 0,
            51, 8, 1, 51, 9, 1, 40, 3, 0, 149, 119, 255, 81, 7, 12, 100, 138, 200,
            152, 8, 100, 169, 40, 243, 100, 135, 51, 8, 51, 9, 61, 7, 0, 0, 2, 0,
            51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 154, 148, 170, 130, 4, 3,
        ])

        // Test with various extreme gas values
        let gasValues: [UInt64] = [
            1,
            100,
            10000,
            1_000_000,
            100_000_000,
            10_000_000_000,
        ]

        for gasValue in gasValues {
            let gas = Gas(gasValue)

            let (exitReasonInterpreter, _, _) = await invokePVM(
                config: config,
                executionMode: [],
                blob: fibonacci,
                pc: 0,
                gas: gas,
                argumentData: Data([5]),
                ctx: nil
            )

            let (exitReasonSandbox, _, _) = await invokePVM(
                config: config,
                executionMode: .sandboxed,
                blob: fibonacci,
                pc: 0,
                gas: gas,
                argumentData: Data([5]),
                ctx: nil
            )

            // Both should handle extreme gas values consistently
            #expect(
                exitReasonInterpreter == exitReasonSandbox,
                "Extreme gas (\(gasValue)): Exit reasons differ"
            )

            logger.info("Extreme gas test (\(gasValue)): both modes produced \(exitReasonInterpreter)")
        }
    }

    // MARK: - Maximum Argument Size

    @Test func stress_maximumArgumentSize() async throws {
        let config = DefaultPvmConfig()

        let sumToN = Data([
            0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 46, 0, 0, 0, 0, 0, 38, 128, 119, 0,
            51, 8, 0, 100, 121, 40, 3, 0, 200, 137, 8, 149, 153, 255, 86, 9, 250,
            61, 8, 0, 0, 2, 0, 51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 77, 18,
            36, 24,
        ])

        // Test with maximum argument size (1MB)
        let maxArgument = Data(repeating: 0xFF, count: 1_048_576)

        let (exitReasonInterpreter, _, _) = await invokePVM(
            config: config,
            executionMode: [],
            blob: sumToN,
            pc: 0,
            gas: Gas(10_000_000),
            argumentData: maxArgument,
            ctx: nil
        )

        let (exitReasonSandbox, _, _) = await invokePVM(
            config: config,
            executionMode: .sandboxed,
            blob: sumToN,
            pc: 0,
            gas: Gas(10_000_000),
            argumentData: maxArgument,
            ctx: nil
        )

        // Both should handle max argument consistently
        #expect(
            exitReasonInterpreter == exitReasonSandbox,
            "Max argument: Exit reasons differ"
        )

        logger.info("Max argument stress test: both modes handled 1MB argument (exit: \(exitReasonInterpreter))")
    }

    // MARK: - Rapid Sequential Execution

    @Test func stress_rapidSequentialExecution() async throws {
        let config = DefaultPvmConfig()

        let sumToN = Data([
            0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 46, 0, 0, 0, 0, 0, 38, 128, 119, 0,
            51, 8, 0, 100, 121, 40, 3, 0, 200, 137, 8, 149, 153, 255, 86, 9, 250,
            61, 8, 0, 0, 2, 0, 51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 77, 18,
            36, 24,
        ])

        // Run the same program multiple times in both modes
        let iterations = 10

        for _ in 0 ..< iterations {
            let (_, _, outputInterpreter) = await invokePVM(
                config: config,
                executionMode: [],
                blob: sumToN,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([7]),
                ctx: nil
            )

            let (_, _, outputSandbox) = await invokePVM(
                config: config,
                executionMode: .sandboxed,
                blob: sumToN,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([7]),
                ctx: nil
            )

            #expect(outputInterpreter == outputSandbox, "Rapid execution: Outputs differ")
        }

        logger.info("Rapid sequential execution stress test: \(iterations) iterations completed")
    }

    // MARK: - Memory Stress Tests

    @Test func stress_memoryPatterns() async throws {
        let config = DefaultPvmConfig()

        let sumToN = Data([
            0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 46, 0, 0, 0, 0, 0, 38, 128, 119, 0,
            51, 8, 0, 100, 121, 40, 3, 0, 200, 137, 8, 149, 153, 255, 86, 9, 250,
            61, 8, 0, 0, 2, 0, 51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 77, 18,
            36, 24,
        ])

        // Test with various memory patterns in arguments
        let memoryPatterns: [(Data, String)] = [
            (Data(repeating: 0x00, count: 100), "zeros"),
            (Data(repeating: 0xFF, count: 100), "max"),
            (Data(repeating: 0xAA, count: 100), "alternating"),
            (Data((0 ..< 100).map { UInt8(truncatingIfNeeded: $0) }), "sequential"),
            (Data((0 ..< 100).reversed().map { UInt8(truncatingIfNeeded: $0) }), "reverse"),
        ]

        for (argument, patternName) in memoryPatterns {
            let (exitReasonInterpreter, _, outputInterpreter) = await invokePVM(
                config: config,
                executionMode: [],
                blob: sumToN,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: argument,
                ctx: nil
            )

            let (exitReasonSandbox, _, outputSandbox) = await invokePVM(
                config: config,
                executionMode: .sandboxed,
                blob: sumToN,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: argument,
                ctx: nil
            )

            #expect(
                exitReasonInterpreter == exitReasonSandbox,
                "Memory pattern '\(patternName)': Exit reasons differ"
            )

            #expect(
                outputInterpreter == outputSandbox,
                "Memory pattern '\(patternName)': Outputs differ"
            )

            logger.info("Memory pattern '\(patternName)'': both modes handled identically")
        }
    }

    // MARK: - Concurrency Stress Test

    @Test func stress_concurrentExecution() async throws {
        let config = DefaultPvmConfig()

        let sumToN = Data([
            0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 46, 0, 0, 0, 0, 0, 38, 128, 119, 0,
            51, 8, 0, 100, 121, 40, 3, 0, 200, 137, 8, 149, 153, 255, 86, 9, 250,
            61, 8, 0, 0, 2, 0, 51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 77, 18,
            36, 24,
        ])

        // Run tests concurrently in both modes
        async let resultInterpreter = Task {
            await invokePVM(
                config: DefaultPvmConfig(),
                executionMode: [],
                blob: sumToN,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([12]),
                ctx: nil
            )
        }.value

        async let resultSandbox = Task {
            await invokePVM(
                config: DefaultPvmConfig(),
                executionMode: .sandboxed,
                blob: sumToN,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([12]),
                ctx: nil
            )
        }.value

        // Run both concurrently and await results
        let (exitReasonInterpreter, _, outputInterpreter) = await resultInterpreter
        let (exitReasonSandbox, _, outputSandbox) = await resultSandbox

        // Verify results match even when run concurrently
        #expect(exitReasonInterpreter == exitReasonSandbox)
        #expect(outputInterpreter == outputSandbox)

        logger.info("Concurrent execution stress test: both modes produced identical results")
    }

    // MARK: - Zero Edge Cases

    @Test func stress_zeroInputs() async throws {
        let config = DefaultPvmConfig()

        // Test with program that handles zero inputs
        let sumToN = Data([
            0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 46, 0, 0, 0, 0, 0, 38, 128, 119, 0,
            51, 8, 0, 100, 121, 40, 3, 0, 200, 137, 8, 149, 153, 255, 86, 9, 250,
            61, 8, 0, 0, 2, 0, 51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 77, 18,
            36, 24,
        ])

        let (exitReasonInterpreter, _, outputInterpreter) = await invokePVM(
            config: config,
            executionMode: [],
            blob: sumToN,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data([0]),
            ctx: nil
        )

        let (exitReasonSandbox, _, outputSandbox) = await invokePVM(
            config: config,
            executionMode: .sandboxed,
            blob: sumToN,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data([0]),
            ctx: nil
        )

        #expect(exitReasonInterpreter == exitReasonSandbox)
        #expect(outputInterpreter == outputSandbox)

        // sum(0) = 0
        let valueInterpreter: UInt32 = if let output = outputInterpreter, output.count >= MemoryLayout<UInt32>.size {
            output.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        } else {
            0
        }

        let valueSandbox: UInt32 = if let output = outputSandbox, output.count >= MemoryLayout<UInt32>.size {
            output.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        } else {
            0
        }

        #expect(valueInterpreter == 0, "Zero input: Interpreter should output 0, got \(valueInterpreter)")
        #expect(valueSandbox == 0, "Zero input: Sandbox should output 0, got \(valueSandbox)")

        logger.info("Zero input stress test: both modes correctly produced 0")
    }

    // MARK: - Boundary Condition Tests

    @Test func stress_boundaryConditions() async throws {
        let config = DefaultPvmConfig()

        // Test various boundary conditions
        let boundaryTests: [(UInt8, String)] = [
            (0, "minimum input"),
            (255, "maximum byte input"),
            (128, "mid-range input"),
        ]

        for (input, description) in boundaryTests {
            let fibonacci = Data([
                0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 61, 0, 0, 0, 0, 0, 51, 128, 119, 0,
                51, 8, 1, 51, 9, 1, 40, 3, 0, 149, 119, 255, 81, 7, 12, 100, 138, 200,
                152, 8, 100, 169, 40, 243, 100, 135, 51, 8, 51, 9, 61, 7, 0, 0, 2, 0,
                51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 154, 148, 170, 130, 4, 3,
            ])

            let (_, _, outputInterpreter) = await invokePVM(
                config: config,
                executionMode: [],
                blob: fibonacci,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([input]),
                ctx: nil
            )

            let (_, _, outputSandbox) = await invokePVM(
                config: config,
                executionMode: .sandboxed,
                blob: fibonacci,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([input]),
                ctx: nil
            )

            #expect(outputInterpreter == outputSandbox, "Boundary test '\(description)': Outputs differ")

            logger.info("Boundary test '\(description)': both modes produced consistent results")
        }
    }
}
