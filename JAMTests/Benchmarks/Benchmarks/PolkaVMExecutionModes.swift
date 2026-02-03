import Benchmark
import Foundation
import PolkaVM
import Utils

/// Benchmarks comparing PolkaVM execution modes: Interpreter vs Sandbox
///
/// These benchmarks measure the performance difference between:
/// - Interpreter mode: Direct execution using VMStateInterpreter + Engine
/// - Sandbox mode: Execution in child process with isolation
func polkaVMExecutionModeBenchmarks() {
    Benchmark.defaultConfiguration.timeUnits = BenchmarkTimeUnits.microseconds

    // Use default config for benchmarking
    let config = DefaultPvmConfig()

    // MARK: - Test Programs

    // Minimal program that halts immediately
    let emptyProgram = Data([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0])

    // Recursive Fibonacci calculation
    let fibonacciProgram = Data([
        0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 61, 0, 0, 0, 0, 0, 51, 128, 119, 0,
        51, 8, 1, 51, 9, 1, 40, 3, 0, 149, 119, 255, 81, 7, 12, 100, 138, 200,
        152, 8, 100, 169, 40, 243, 100, 135, 51, 8, 51, 9, 61, 7, 0, 0, 2, 0,
        51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 154, 148, 170, 130, 4, 3,
    ])

    // Sum of integers from 0 to N
    let sumToNProgram = Data([
        0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 46, 0, 0, 0, 0, 0, 38, 128, 119, 0,
        51, 8, 0, 100, 121, 40, 3, 0, 200, 137, 8, 149, 153, 255, 86, 9, 250,
        61, 8, 0, 0, 2, 0, 51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 77, 18,
        36, 24,
    ])

    // MARK: - Interpreter Mode Benchmarks

    Benchmark("vm.mode.interpreter.empty") { benchmark in
        benchmark.startMeasurement()
        let (exitReason, _, _) = await invokePVM(
            config: config,
            executionMode: [], // Interpreter mode
            blob: emptyProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data(),
            ctx: nil,
        )
        benchmark.stopMeasurement()
        blackHole(exitReason)
    }

    Benchmark("vm.mode.interpreter.fibonacci") { benchmark in
        benchmark.startMeasurement()
        let (exitReason, _, _) = await invokePVM(
            config: config,
            executionMode: [], // Interpreter mode
            blob: fibonacciProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data([8]),
            ctx: nil,
        )
        benchmark.stopMeasurement()
        blackHole(exitReason)
    }

    Benchmark("vm.mode.interpreter.sumToN") { benchmark in
        benchmark.startMeasurement()
        let (exitReason, _, _) = await invokePVM(
            config: config,
            executionMode: [], // Interpreter mode
            blob: sumToNProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data([10]),
            ctx: nil,
        )
        benchmark.stopMeasurement()
        blackHole(exitReason)
    }

    // MARK: - Sandbox Mode Benchmarks

    Benchmark("vm.mode.sandbox.empty") { benchmark in
        benchmark.startMeasurement()
        let (exitReason, _, _) = await invokePVM(
            config: config,
            executionMode: .sandboxed, // Sandbox mode
            blob: emptyProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data(),
            ctx: nil,
        )
        benchmark.stopMeasurement()
        blackHole(exitReason)
    }

    Benchmark("vm.mode.sandbox.fibonacci") { benchmark in
        benchmark.startMeasurement()
        let (exitReason, _, _) = await invokePVM(
            config: config,
            executionMode: .sandboxed, // Sandbox mode
            blob: fibonacciProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data([8]),
            ctx: nil,
        )
        benchmark.stopMeasurement()
        blackHole(exitReason)
    }

    Benchmark("vm.mode.sandbox.sumToN") { benchmark in
        benchmark.startMeasurement()
        let (exitReason, _, _) = await invokePVM(
            config: config,
            executionMode: .sandboxed, // Sandbox mode
            blob: sumToNProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data([10]),
            ctx: nil,
        )
        benchmark.stopMeasurement()
        blackHole(exitReason)
    }

    // MARK: - Batch Execution Benchmarks

    Benchmark("vm.mode.interpreter.batch100") { benchmark in
        benchmark.startMeasurement()
        for _ in 0 ..< 100 {
            let (exitReason, _, _) = await invokePVM(
                config: config,
                executionMode: [], // Interpreter mode
                blob: emptyProgram,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data(),
                ctx: nil,
            )
            blackHole(exitReason)
        }
        benchmark.stopMeasurement()
    }

    Benchmark("vm.mode.sandbox.batch100") { benchmark in
        benchmark.startMeasurement()
        for _ in 0 ..< 100 {
            let (exitReason, _, _) = await invokePVM(
                config: config,
                executionMode: .sandboxed, // Sandbox mode
                blob: emptyProgram,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data(),
                ctx: nil,
            )
            blackHole(exitReason)
        }
        benchmark.stopMeasurement()
    }

    // MARK: - Heavy Computation Benchmarks (Larger Programs)

    Benchmark("vm.mode.interpreter.heavyFibonacci", configuration: .init(timeUnits: .milliseconds)) { benchmark in
        benchmark.startMeasurement()
        let (exitReason, _, _) = await invokePVM(
            config: config,
            executionMode: [], // Interpreter mode
            blob: fibonacciProgram,
            pc: 0,
            gas: Gas(10_000_000),
            argumentData: Data([20]),
            ctx: nil,
        )
        benchmark.stopMeasurement()
        blackHole(exitReason)
    }

    Benchmark("vm.mode.sandbox.heavyFibonacci", configuration: .init(timeUnits: .milliseconds)) { benchmark in
        benchmark.startMeasurement()
        let (exitReason, _, _) = await invokePVM(
            config: config,
            executionMode: .sandboxed, // Sandbox mode
            blob: fibonacciProgram,
            pc: 0,
            gas: Gas(10_000_000),
            argumentData: Data([20]),
            ctx: nil,
        )
        benchmark.stopMeasurement()
        blackHole(exitReason)
    }

    // MARK: - Memory-Intensive Benchmarks

    Benchmark("vm.mode.interpreter.memoryIntensive") { benchmark in
        benchmark.startMeasurement()
        let (exitReason, _, _) = await invokePVM(
            config: config,
            executionMode: [], // Interpreter mode
            blob: sumToNProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data([50]), // Larger input = more memory operations
            ctx: nil,
        )
        benchmark.stopMeasurement()
        blackHole(exitReason)
    }

    Benchmark("vm.mode.sandbox.memoryIntensive") { benchmark in
        benchmark.startMeasurement()
        let (exitReason, _, _) = await invokePVM(
            config: config,
            executionMode: .sandboxed, // Sandbox mode
            blob: sumToNProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data([50]), // Larger input = more memory operations
            ctx: nil,
        )
        benchmark.stopMeasurement()
        blackHole(exitReason)
    }

    // MARK: - Repeated Execution Benchmarks

    Benchmark("vm.mode.interpreter.repeated") { benchmark in
        benchmark.startMeasurement()
        for i in 0 ..< 10 {
            let (exitReason, _, _) = await invokePVM(
                config: config,
                executionMode: [], // Interpreter mode
                blob: sumToNProgram,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([UInt8(i)]),
                ctx: nil,
            )
            blackHole(exitReason)
        }
        benchmark.stopMeasurement()
    }

    Benchmark("vm.mode.sandbox.repeated") { benchmark in
        benchmark.startMeasurement()
        for i in 0 ..< 10 {
            let (exitReason, _, _) = await invokePVM(
                config: config,
                executionMode: .sandboxed, // Sandbox mode
                blob: sumToNProgram,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([UInt8(i)]),
                ctx: nil,
            )
            blackHole(exitReason)
        }
        benchmark.stopMeasurement()
    }

    // MARK: - Throughput Benchmarks

    Benchmark("vm.mode.interpreter.throughput", configuration: .init(timeUnits: .milliseconds)) { benchmark in
        benchmark.startMeasurement()
        for _ in 0 ..< 50 {
            let (exitReason, _, _) = await invokePVM(
                config: config,
                executionMode: [], // Interpreter mode
                blob: fibonacciProgram,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([10]),
                ctx: nil,
            )
            blackHole(exitReason)
        }
        benchmark.stopMeasurement()
    }

    Benchmark("vm.mode.sandbox.throughput", configuration: .init(timeUnits: .milliseconds)) { benchmark in
        benchmark.startMeasurement()
        for _ in 0 ..< 50 {
            let (exitReason, _, _) = await invokePVM(
                config: config,
                executionMode: .sandboxed, // Sandbox mode
                blob: fibonacciProgram,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([10]),
                ctx: nil,
            )
            blackHole(exitReason)
        }
        benchmark.stopMeasurement()
    }
}
