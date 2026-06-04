import Benchmark
import Foundation

// This file consolidates all benchmarks into a single executable
// The Benchmark package will automatically discover and register all benchmarks

private func configureCIBenchmarkDefaultsIfNeeded() {
    guard BokaBenchmark.isCIFastMode else {
        return
    }

    print("CI benchmark mode enabled (maxDuration=100ms, maxIterations=8, warmupIterations=1)")

    var configuration = Benchmark.defaultConfiguration
    // Keep CI baselines deterministic and bounded on slower self-hosted runners.
    configuration.maxDuration = .milliseconds(100)
    configuration.maxIterations = min(configuration.maxIterations, 8)
    configuration.warmupIterations = 1
    Benchmark.defaultConfiguration = configuration
}

// MARK: - Entry Point

let benchmarks: @Sendable () -> Void = {
    BokaBenchmark.applyDefaultConfiguration()
    configureCIBenchmarkDefaultsIfNeeded()

    // Call all benchmark registration functions
    merkleTrieBenchmarks()
    stateBackendBenchmarks()
    fuzzingStateCopyBenchmarks()
    runtimeBenchmarks()
    blockchainBenchmarks()
    rocksdbBenchmarks()
    rocksdbProfilingBenchmarks()
    polkaVMBenchmarks()
    polkaVMExecutionModeBenchmarks()
    jitPerformanceBenchmarks()
    validatorBenchmarks()
    testVectorsBenchmarks()
}
