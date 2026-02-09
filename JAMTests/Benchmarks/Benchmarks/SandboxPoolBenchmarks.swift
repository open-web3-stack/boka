import Benchmark
import Foundation
import PolkaVM
import Utils

/// Benchmarks for sandbox pool configurations and performance
func sandboxPoolBenchmarks() {
    Benchmark.defaultConfiguration.timeUnits = .microseconds

    // Test programs
    let emptyProgram = Data([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0])

    let fibonacciProgram = Data([
        0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 61, 0, 0, 0, 0, 0, 51, 128, 119, 0,
        51, 8, 1, 51, 9, 1, 40, 3, 0, 149, 119, 255, 81, 7, 12, 100, 138, 200,
        152, 8, 100, 169, 40, 243, 100, 135, 51, 8, 51, 9, 61, 7, 0, 0, 2, 0,
        51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 154, 148, 170, 130, 4, 3,
    ])

    let sumToNProgram = Data([
        0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 46, 0, 0, 0, 0, 0, 38, 128, 119, 0,
        51, 8, 0, 100, 121, 40, 3, 0, 200, 137, 8, 149, 153, 255, 86, 9, 250,
        61, 8, 0, 0, 2, 0, 51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 77, 18,
        36, 24,
    ])
    registerPoolConfigurationBenchmarks(emptyProgram: emptyProgram)
    registerPoolSizeBenchmarks(emptyProgram: emptyProgram)
    registerConcurrentBenchmarks(fibonacciProgram: fibonacciProgram)
    registerComparisonBenchmarks(emptyProgram: emptyProgram, fibonacciProgram: fibonacciProgram)
    registerBatchBenchmarks(emptyProgram: emptyProgram)
    registerThroughputBenchmarks(fibonacciProgram: fibonacciProgram)
    registerMemoryBenchmarks(sumToNProgram: sumToNProgram)
    registerQueueDepthBenchmarks(emptyProgram: emptyProgram)
}

private func registerPoolConfigurationBenchmarks(emptyProgram: Data) {
    // MARK: - Pool Configuration Comparisons

    Benchmark("pool.config.throughput.single") { benchmark in
        let config = SandboxPoolConfiguration.throughputOptimized
        let executor = Executor.pooled(
            mode: .sandboxed,
            config: DefaultPvmConfig(),
            poolConfig: config,
        )

        benchmark.startMeasurement()
        let result = await executor.execute(
            blob: emptyProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: nil,
            ctx: nil,
        )
        benchmark.stopMeasurement()
        blackHole(result)
    }

    Benchmark("pool.config.latency.single") { benchmark in
        let config = SandboxPoolConfiguration.latencyOptimized
        let executor = Executor.pooled(
            mode: .sandboxed,
            config: DefaultPvmConfig(),
            poolConfig: config,
        )

        benchmark.startMeasurement()
        let result = await executor.execute(
            blob: emptyProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: nil,
            ctx: nil,
        )
        benchmark.stopMeasurement()
        blackHole(result)
    }

    Benchmark("pool.config.memoryEfficient.single") { benchmark in
        let config = SandboxPoolConfiguration.memoryEfficient
        let executor = Executor.pooled(
            mode: .sandboxed,
            config: DefaultPvmConfig(),
            poolConfig: config,
        )

        benchmark.startMeasurement()
        let result = await executor.execute(
            blob: emptyProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: nil,
            ctx: nil,
        )
        benchmark.stopMeasurement()
        blackHole(result)
    }

    Benchmark("pool.config.development.single") { benchmark in
        let config = SandboxPoolConfiguration.development
        let executor = Executor.pooled(
            mode: .sandboxed,
            config: DefaultPvmConfig(),
            poolConfig: config,
        )

        benchmark.startMeasurement()
        let result = await executor.execute(
            blob: emptyProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: nil,
            ctx: nil,
        )
        benchmark.stopMeasurement()
        blackHole(result)
    }
}

private func registerPoolSizeBenchmarks(emptyProgram: Data) {
    // MARK: - Pool Size Benchmarks

    Benchmark("pool.size.2.single") { benchmark in
        var config = SandboxPoolConfiguration.throughputOptimized
        config.poolSize = 2
        let executor = Executor.pooled(
            mode: .sandboxed,
            config: DefaultPvmConfig(),
            poolConfig: config,
        )

        benchmark.startMeasurement()
        let result = await executor.execute(
            blob: emptyProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: nil,
            ctx: nil,
        )
        benchmark.stopMeasurement()
        blackHole(result)
    }

    Benchmark("pool.size.4.single") { benchmark in
        var config = SandboxPoolConfiguration.throughputOptimized
        config.poolSize = 4
        let executor = Executor.pooled(
            mode: .sandboxed,
            config: DefaultPvmConfig(),
            poolConfig: config,
        )

        benchmark.startMeasurement()
        let result = await executor.execute(
            blob: emptyProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: nil,
            ctx: nil,
        )
        benchmark.stopMeasurement()
        blackHole(result)
    }

    Benchmark("pool.size.8.single") { benchmark in
        var config = SandboxPoolConfiguration.throughputOptimized
        config.poolSize = 8
        let executor = Executor.pooled(
            mode: .sandboxed,
            config: DefaultPvmConfig(),
            poolConfig: config,
        )

        benchmark.startMeasurement()
        let result = await executor.execute(
            blob: emptyProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: nil,
            ctx: nil,
        )
        benchmark.stopMeasurement()
        blackHole(result)
    }

    Benchmark("pool.size.16.single") { benchmark in
        var config = SandboxPoolConfiguration.throughputOptimized
        config.poolSize = 16
        let executor = Executor.pooled(
            mode: .sandboxed,
            config: DefaultPvmConfig(),
            poolConfig: config,
        )

        benchmark.startMeasurement()
        let result = await executor.execute(
            blob: emptyProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: nil,
            ctx: nil,
        )
        benchmark.stopMeasurement()
        blackHole(result)
    }
}

private func registerConcurrentBenchmarks(fibonacciProgram: Data) {
    // MARK: - Concurrent Execution Benchmarks

    Benchmark("pool.concurrent.fibonacci", configuration: .init(timeUnits: .milliseconds)) { benchmark in
        let config = SandboxPoolConfiguration.throughputOptimized
        let executor = Executor.pooled(
            mode: .sandboxed,
            config: DefaultPvmConfig(),
            poolConfig: config,
        )

        benchmark.startMeasurement()

        // Execute 50 concurrent requests
        await withTaskGroup(of: Void.self) { group in
            let exec = executor
            for _ in 0 ..< 50 {
                group.addTask {
                    let result = await exec.execute(
                        blob: fibonacciProgram,
                        pc: 0,
                        gas: Gas(1_000_000),
                        argumentData: Data([10]),
                        ctx: nil,
                    )
                    blackHole(result)
                }
            }
        }

        benchmark.stopMeasurement()
    }
}

private func registerComparisonBenchmarks(emptyProgram: Data, fibonacciProgram: Data) {
    // MARK: - Pooled vs Non-Pooled Comparison

    Benchmark("pool.comparison.pooled.empty") { benchmark in
        let config = SandboxPoolConfiguration.throughputOptimized
        let executor = Executor.pooled(
            mode: .sandboxed,
            config: DefaultPvmConfig(),
            poolConfig: config,
        )

        benchmark.startMeasurement()
        let result = await executor.execute(
            blob: emptyProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: nil,
            ctx: nil,
        )
        benchmark.stopMeasurement()
        blackHole(result)
    }

    Benchmark("pool.comparison.nonpooled.empty") { benchmark in
        let executor = Executor(
            mode: .sandboxed,
            config: DefaultPvmConfig(),
        )

        benchmark.startMeasurement()
        let result = await executor.execute(
            blob: emptyProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: nil,
            ctx: nil,
        )
        benchmark.stopMeasurement()
        blackHole(result)
    }

    Benchmark("pool.comparison.pooled.fibonacci") { benchmark in
        let config = SandboxPoolConfiguration.throughputOptimized
        let executor = Executor.pooled(
            mode: .sandboxed,
            config: DefaultPvmConfig(),
            poolConfig: config,
        )

        benchmark.startMeasurement()
        let result = await executor.execute(
            blob: fibonacciProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data([8]),
            ctx: nil,
        )
        benchmark.stopMeasurement()
        blackHole(result)
    }

    Benchmark("pool.comparison.nonpooled.fibonacci") { benchmark in
        let executor = Executor(
            mode: .sandboxed,
            config: DefaultPvmConfig(),
        )

        benchmark.startMeasurement()
        let result = await executor.execute(
            blob: fibonacciProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data([8]),
            ctx: nil,
        )
        benchmark.stopMeasurement()
        blackHole(result)
    }
}

private func registerBatchBenchmarks(emptyProgram: Data) {
    // MARK: - Batch Performance (Key Metric!)

    Benchmark("pool.batch.pooled.100", configuration: .init(timeUnits: .milliseconds)) { benchmark in
        let config = SandboxPoolConfiguration.throughputOptimized
        let executor = Executor.pooled(
            mode: .sandboxed,
            config: DefaultPvmConfig(),
            poolConfig: config,
        )

        benchmark.startMeasurement()

        for _ in 0 ..< 100 {
            let result = await executor.execute(
                blob: emptyProgram,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: nil,
                ctx: nil,
            )
            blackHole(result)
        }

        benchmark.stopMeasurement()
    }

    Benchmark("pool.batch.nonpooled.100", configuration: .init(timeUnits: .milliseconds)) { benchmark in
        let executor = Executor(
            mode: .sandboxed,
            config: DefaultPvmConfig(),
        )

        benchmark.startMeasurement()

        for _ in 0 ..< 100 {
            let result = await executor.execute(
                blob: emptyProgram,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: nil,
                ctx: nil,
            )
            blackHole(result)
        }

        benchmark.stopMeasurement()
    }
}

private func registerThroughputBenchmarks(fibonacciProgram: Data) {
    // MARK: - Throughput Benchmarks

    Benchmark("pool.throughput.pooled.fibonacci", configuration: .init(timeUnits: .milliseconds)) { benchmark in
        let config = SandboxPoolConfiguration.throughputOptimized
        let executor = Executor.pooled(
            mode: .sandboxed,
            config: DefaultPvmConfig(),
            poolConfig: config,
        )

        benchmark.startMeasurement()

        for _ in 0 ..< 50 {
            let result = await executor.execute(
                blob: fibonacciProgram,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([10]),
                ctx: nil,
            )
            blackHole(result)
        }

        benchmark.stopMeasurement()
    }

    Benchmark("pool.throughput.nonpooled.fibonacci", configuration: .init(timeUnits: .milliseconds)) { benchmark in
        let executor = Executor(
            mode: .sandboxed,
            config: DefaultPvmConfig(),
        )

        benchmark.startMeasurement()

        for _ in 0 ..< 50 {
            let result = await executor.execute(
                blob: fibonacciProgram,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([10]),
                ctx: nil,
            )
            blackHole(result)
        }

        benchmark.stopMeasurement()
    }
}

private func registerMemoryBenchmarks(sumToNProgram: Data) {
    // MARK: - Memory Intensive Workloads

    Benchmark("pool.memory.pooled.sumToN") { benchmark in
        let config = SandboxPoolConfiguration.throughputOptimized
        let executor = Executor.pooled(
            mode: .sandboxed,
            config: DefaultPvmConfig(),
            poolConfig: config,
        )

        benchmark.startMeasurement()
        let result = await executor.execute(
            blob: sumToNProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data([50]),
            ctx: nil,
        )
        benchmark.stopMeasurement()
        blackHole(result)
    }

    Benchmark("pool.memory.nonpooled.sumToN") { benchmark in
        let executor = Executor(
            mode: .sandboxed,
            config: DefaultPvmConfig(),
        )

        benchmark.startMeasurement()
        let result = await executor.execute(
            blob: sumToNProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data([50]),
            ctx: nil,
        )
        benchmark.stopMeasurement()
        blackHole(result)
    }
}

private func registerQueueDepthBenchmarks(emptyProgram: Data) {
    // MARK: - Queue Depth Impact

    Benchmark("pool.queueDepth.10") { benchmark in
        var config = SandboxPoolConfiguration.throughputOptimized
        config.maxQueueDepth = 10
        let executor = Executor.pooled(
            mode: .sandboxed,
            config: DefaultPvmConfig(),
            poolConfig: config,
        )

        benchmark.startMeasurement()
        let result = await executor.execute(
            blob: emptyProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: nil,
            ctx: nil,
        )
        benchmark.stopMeasurement()
        blackHole(result)
    }

    Benchmark("pool.queueDepth.1000") { benchmark in
        var config = SandboxPoolConfiguration.throughputOptimized
        config.maxQueueDepth = 1000
        let executor = Executor.pooled(
            mode: .sandboxed,
            config: DefaultPvmConfig(),
            poolConfig: config,
        )

        benchmark.startMeasurement()
        let result = await executor.execute(
            blob: emptyProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: nil,
            ctx: nil,
        )
        benchmark.stopMeasurement()
        blackHole(result)
    }

    Benchmark("pool.queueDepth.10000") { benchmark in
        var config = SandboxPoolConfiguration.throughputOptimized
        config.maxQueueDepth = 10000
        let executor = Executor.pooled(
            mode: .sandboxed,
            config: DefaultPvmConfig(),
            poolConfig: config,
        )

        benchmark.startMeasurement()
        let result = await executor.execute(
            blob: emptyProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: nil,
            ctx: nil,
        )
        benchmark.stopMeasurement()
        blackHole(result)
    }
}
