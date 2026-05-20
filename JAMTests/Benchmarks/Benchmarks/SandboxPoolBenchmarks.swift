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

private func benchmarkPoolConfig(_ base: SandboxPoolConfiguration) -> SandboxPoolConfiguration {
    guard BokaBenchmark.isCIFastMode else {
        return base
    }

    var config = base
    config.poolSize = 1
    config.maxQueueDepth = min(config.maxQueueDepth, 10)
    config.workerWaitTimeout = min(config.workerWaitTimeout, 0.01)
    config.executionTimeout = min(config.executionTimeout, 0.1)
    config.enableWorkerRecycling = false
    config.healthCheckInterval = 0
    config.allowOverflowWorkers = false
    config.maxOverflowWorkers = 0
    config.exhaustionPolicy = .failFast
    return config
}

private func registerPoolConfigurationBenchmarks(emptyProgram: Data) {
    // MARK: - Pool Configuration Comparisons

    Benchmark("pool.config.throughput.single") { benchmark in
        let config = benchmarkPoolConfig(.throughputOptimized)
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
        let config = benchmarkPoolConfig(.latencyOptimized)
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
        let config = benchmarkPoolConfig(.memoryEfficient)
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
        let config = benchmarkPoolConfig(.development)
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
        config = benchmarkPoolConfig(config)
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
        config = benchmarkPoolConfig(config)
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
        config = benchmarkPoolConfig(config)
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
        config = benchmarkPoolConfig(config)
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

    Benchmark("pool.concurrent.fibonacci", configuration: BokaBenchmark.milliseconds) { benchmark in
        let config = benchmarkPoolConfig(.throughputOptimized)
        let executor = Executor.pooled(
            mode: .sandboxed,
            config: DefaultPvmConfig(),
            poolConfig: config,
        )
        let requestCount = BokaBenchmark.operationCount(50, ciFastCount: 1)

        benchmark.startMeasurement()

        await withTaskGroup(of: Void.self) { group in
            let exec = executor
            for _ in 0 ..< requestCount {
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
        let config = benchmarkPoolConfig(.throughputOptimized)
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
        let config = benchmarkPoolConfig(.throughputOptimized)
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

    Benchmark("pool.batch.pooled.100", configuration: BokaBenchmark.milliseconds) { benchmark in
        let config = benchmarkPoolConfig(.throughputOptimized)
        let executor = Executor.pooled(
            mode: .sandboxed,
            config: DefaultPvmConfig(),
            poolConfig: config,
        )
        let executionCount = BokaBenchmark.operationCount(100, ciFastCount: 1)

        benchmark.startMeasurement()

        for _ in 0 ..< executionCount {
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

    Benchmark("pool.batch.nonpooled.100", configuration: BokaBenchmark.milliseconds) { benchmark in
        let executor = Executor(
            mode: .sandboxed,
            config: DefaultPvmConfig(),
        )
        let executionCount = BokaBenchmark.operationCount(100, ciFastCount: 1)

        benchmark.startMeasurement()

        for _ in 0 ..< executionCount {
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

    Benchmark("pool.throughput.pooled.fibonacci", configuration: BokaBenchmark.milliseconds) { benchmark in
        let config = benchmarkPoolConfig(.throughputOptimized)
        let executor = Executor.pooled(
            mode: .sandboxed,
            config: DefaultPvmConfig(),
            poolConfig: config,
        )
        let executionCount = BokaBenchmark.operationCount(50, ciFastCount: 1)

        benchmark.startMeasurement()

        for _ in 0 ..< executionCount {
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

    Benchmark("pool.throughput.nonpooled.fibonacci", configuration: BokaBenchmark.milliseconds) { benchmark in
        let executor = Executor(
            mode: .sandboxed,
            config: DefaultPvmConfig(),
        )
        let executionCount = BokaBenchmark.operationCount(50, ciFastCount: 1)

        benchmark.startMeasurement()

        for _ in 0 ..< executionCount {
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
        let config = benchmarkPoolConfig(.throughputOptimized)
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
        config = benchmarkPoolConfig(config)
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
        config = benchmarkPoolConfig(config)
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
        config = benchmarkPoolConfig(config)
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
