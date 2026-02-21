import Benchmark
import Foundation

// This file consolidates all benchmarks into a single executable
// The Benchmark package will automatically discover and register all benchmarks

private func isTruthyEnv(_ value: String?) -> Bool {
    guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
        return false
    }
    return !["", "0", "false", "no", "off"].contains(normalized)
}

private func configureCIBenchmarkDefaultsIfNeeded() {
    guard isTruthyEnv(ProcessInfo.processInfo.environment["BOKA_BENCHMARK_CI_FAST"]) else {
        return
    }

    print("CI benchmark mode enabled (maxDuration=100ms, maxIterations=8, warmupIterations=0)")

    var configuration = Benchmark.defaultConfiguration
    // Keep CI baselines deterministic and bounded on slower self-hosted runners.
    configuration.maxDuration = .milliseconds(100)
    configuration.maxIterations = min(configuration.maxIterations, 8)
    configuration.warmupIterations = 0
    Benchmark.defaultConfiguration = configuration
}

// MARK: - Entry Point

let benchmarks: @Sendable () -> Void = {
    configureCIBenchmarkDefaultsIfNeeded()

    // Call all benchmark registration functions
    merkleTrieBenchmarks()
    stateBackendBenchmarks()
    runtimeBenchmarks()
    blockchainBenchmarks()
    rocksdbBenchmarks()
    rocksdbProfilingBenchmarks()
    polkaVMBenchmarks()
    polkaVMExecutionModeBenchmarks()
    jITSandboxPerformanceBenchmarks()
    sandboxPoolBenchmarks()
    validatorBenchmarks()
    testVectorsBenchmarks()
}
