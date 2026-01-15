import Benchmark
import Foundation
import PolkaVM
import Utils

func polkaVMBenchmarks() {
    Benchmark.defaultConfiguration.timeUnits = BenchmarkTimeUnits.microseconds

    // Use default config for benchmarking
    let config = DefaultPvmConfig()

    // PVM bytecode: Minimal program that halts immediately
    // Format: [header...]
    let emptyProgram = Data([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0])

    // PVM bytecode: Recursive Fibonacci calculation
    // Format: [header..., ops for fibonacci algorithm]
    let fibonacciProgram = Data([
        0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 61, 0, 0, 0, 0, 0, 51, 128, 119, 0,
        51, 8, 1, 51, 9, 1, 40, 3, 0, 149, 119, 255, 81, 7, 12, 100, 138, 200,
        152, 8, 100, 169, 40, 243, 100, 135, 51, 8, 51, 9, 61, 7, 0, 0, 2, 0,
        51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 154, 148, 170, 130, 4, 3,
    ])

    // PVM bytecode: Sum of integers from 0 to N
    // Format: [header..., ops for summation loop]
    let sumToNProgram = Data([
        0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 46, 0, 0, 0, 0, 0, 38, 128, 119, 0,
        51, 8, 0, 100, 121, 40, 3, 0, 200, 137, 8, 149, 153, 255, 86, 9, 250,
        61, 8, 0, 0, 2, 0, 51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 77, 18,
        36, 24,
    ])

    // MARK: - Simple operations

    Benchmark("vm.contract.transfer") { benchmark in
        benchmark.startMeasurement()
        let (exitReason, _, _) = await invokePVM(
            config: config,
            blob: emptyProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data(),
            ctx: nil
        )
        benchmark.stopMeasurement()
        blackHole(exitReason)
    }

    Benchmark("vm.contract.dex") { benchmark in
        benchmark.startMeasurement()
        let (exitReason, _, _) = await invokePVM(
            config: config,
            blob: fibonacciProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data([8]),
            ctx: nil
        )
        benchmark.stopMeasurement()
        blackHole(exitReason)
    }

    Benchmark("vm.contract.nft") { benchmark in
        benchmark.startMeasurement()
        let (exitReason, _, _) = await invokePVM(
            config: config,
            blob: sumToNProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data([4]),
            ctx: nil
        )
        benchmark.stopMeasurement()
        blackHole(exitReason)
    }

    // MARK: - Batch operations

    Benchmark("vm.batch.contracts") { benchmark in
        benchmark.startMeasurement()
        for _ in 0 ..< 100 {
            let (exitReason, _, _) = await invokePVM(
                config: config,
                blob: emptyProgram,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data(),
                ctx: nil
            )
            blackHole(exitReason)
        }
        benchmark.stopMeasurement()
    }

    Benchmark("vm.state.access.heavy", configuration: .init(timeUnits: .milliseconds)) { benchmark in
        benchmark.startMeasurement()
        // Run fibonacci with larger input for more computation
        let (exitReason, _, _) = await invokePVM(
            config: config,
            blob: fibonacciProgram,
            pc: 0,
            gas: Gas(10_000_000),
            argumentData: Data([20]),
            ctx: nil
        )
        benchmark.stopMeasurement()
        blackHole(exitReason)
    }

    Benchmark("vm.execution.repeated") { benchmark in
        // Benchmark repeated VM execution overhead (10 iterations of sumToN)
        benchmark.startMeasurement()
        for i in 0 ..< 10 {
            let (exitReason, _, _) = await invokePVM(
                config: config,
                blob: sumToNProgram,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([UInt8(i)]),
                ctx: nil
            )
            blackHole(exitReason)
        }
        benchmark.stopMeasurement()
    }

    Benchmark("vm.execution.sequential") { benchmark in
        // Benchmark sequential VM execution overhead (5 iterations of fibonacci)
        benchmark.startMeasurement()
        for _ in 0 ..< 5 {
            let (exitReason, _, _) = await invokePVM(
                config: config,
                blob: fibonacciProgram,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([5]),
                ctx: nil
            )
            blackHole(exitReason)
        }
        benchmark.stopMeasurement()
    }

    // MARK: - Throughput benchmarks

    Benchmark("vm.throughput.instructions", configuration: .init(timeUnits: .milliseconds)) { benchmark in
        benchmark.startMeasurement()
        // Run fibonacci with larger input
        let (exitReason, _, _) = await invokePVM(
            config: config,
            blob: fibonacciProgram,
            pc: 0,
            gas: Gas(10_000_000),
            argumentData: Data([15]),
            ctx: nil
        )
        benchmark.stopMeasurement()
        blackHole(exitReason)
    }

    Benchmark("vm.memory.operations") { benchmark in
        benchmark.startMeasurement()
        // Run sumToN which has memory operations
        let (exitReason, _, _) = await invokePVM(
            config: config,
            blob: sumToNProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data([10]),
            ctx: nil
        )
        benchmark.stopMeasurement()
        blackHole(exitReason)
    }
}
