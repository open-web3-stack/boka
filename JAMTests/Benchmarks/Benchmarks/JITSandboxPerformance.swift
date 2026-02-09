import Benchmark
import Foundation
import PolkaVM
import Utils

/// Benchmarks for JIT and Sandbox performance comparisons
func jITSandboxPerformanceBenchmarks() {
    Benchmark.defaultConfiguration.timeUnits = BenchmarkTimeUnits.microseconds

    let config = DefaultPvmConfig()

    // Sum integers program
    let sumToNProgram = Data([
        0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 46, 0, 0, 0, 0, 0, 38, 128, 119, 0,
        51, 8, 0, 100, 121, 40, 3, 0, 200, 137, 8, 149, 153, 255, 86, 9, 250,
        61, 8, 0, 0, 2, 0, 51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 77, 18,
        36, 24,
    ])

    // Halt program (minimal program)
    let haltProgram = Data([
        1, // 1 jump table entry
        0, 0, 0, 0, 0, 0, 0, 0, // jump table entry 0: offset 0
        0x01, // halt instruction (opcode 1)
    ])

    // MARK: - Execution Mode Comparisons

    Benchmark("jitperf.mode.interpreter", configuration: .init(timeUnits: .milliseconds)) { benchmark in
        benchmark.startMeasurement()
        for _ in 0 ..< 200 {
            let (exitReason, _, _) = await invokePVM(
                config: config,
                executionMode: [],
                blob: sumToNProgram,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([25]),
                ctx: nil,
            )
            blackHole(exitReason)
        }
        benchmark.stopMeasurement()
    }

    Benchmark("jitperf.mode.jit", configuration: .init(timeUnits: .milliseconds)) { benchmark in
        benchmark.startMeasurement()
        for _ in 0 ..< 200 {
            let (exitReason, _, _) = await invokePVM(
                config: config,
                executionMode: .jit,
                blob: sumToNProgram,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([25]),
                ctx: nil,
            )
            blackHole(exitReason)
        }
        benchmark.stopMeasurement()
    }

    Benchmark("jitperf.mode.sandbox", configuration: .init(timeUnits: .milliseconds)) { benchmark in
        benchmark.startMeasurement()
        for _ in 0 ..< 200 {
            let (exitReason, _, _) = await invokePVM(
                config: config,
                executionMode: .sandboxed,
                blob: sumToNProgram,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([25]),
                ctx: nil,
            )
            blackHole(exitReason)
        }
        benchmark.stopMeasurement()
    }

    Benchmark("jitperf.mode.jitSandbox", configuration: .init(timeUnits: .milliseconds)) { benchmark in
        benchmark.startMeasurement()
        for _ in 0 ..< 200 {
            let (exitReason, _, _) = await invokePVM(
                config: config,
                executionMode: [.jit, .sandboxed],
                blob: sumToNProgram,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([25]),
                ctx: nil,
            )
            blackHole(exitReason)
        }
        benchmark.stopMeasurement()
    }

    // MARK: - Stress Test (Massive Iterations)

    Benchmark("jitperf.stress.jit", configuration: .init(timeUnits: .milliseconds)) { benchmark in
        benchmark.startMeasurement()
        for _ in 0 ..< 2000 {
            let (exitReason, _, _) = await invokePVM(
                config: config,
                executionMode: .jit,
                blob: sumToNProgram,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([30]),
                ctx: nil,
            )
            blackHole(exitReason)
        }
        benchmark.stopMeasurement()
    }

    Benchmark("jitperf.stress.jitSandbox", configuration: .init(timeUnits: .milliseconds)) { benchmark in
        benchmark.startMeasurement()
        for _ in 0 ..< 2000 {
            let (exitReason, _, _) = await invokePVM(
                config: config,
                executionMode: [.jit, .sandboxed],
                blob: sumToNProgram,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([30]),
                ctx: nil,
            )
            blackHole(exitReason)
        }
        benchmark.stopMeasurement()
    }

    // MARK: - Minimal Program Comparisons

    Benchmark("jitperf.minimal.jit") { benchmark in
        benchmark.startMeasurement()
        for _ in 0 ..< 100 {
            let (exitReason, _, _) = await invokePVM(
                config: config,
                executionMode: .jit,
                blob: haltProgram,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: nil,
                ctx: nil,
            )
            blackHole(exitReason)
        }
        benchmark.stopMeasurement()
    }

    Benchmark("jitperf.minimal.jitSandbox") { benchmark in
        benchmark.startMeasurement()
        for _ in 0 ..< 100 {
            let (exitReason, _, _) = await invokePVM(
                config: config,
                executionMode: [.jit, .sandboxed],
                blob: haltProgram,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: nil,
                ctx: nil,
            )
            blackHole(exitReason)
        }
        benchmark.stopMeasurement()
    }
}
