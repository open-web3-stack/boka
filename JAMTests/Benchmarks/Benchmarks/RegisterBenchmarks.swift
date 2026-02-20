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

    var configuration = Benchmark.defaultConfiguration
    configuration.maxDuration = .milliseconds(300)
    configuration.maxIterations = min(configuration.maxIterations, 40)
    configuration.warmupIterations = min(configuration.warmupIterations, 1)
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
