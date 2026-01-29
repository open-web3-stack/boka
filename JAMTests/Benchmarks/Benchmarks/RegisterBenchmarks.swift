import Benchmark
import Foundation

// This file consolidates all benchmarks into a single executable
// The Benchmark package will automatically discover and register all benchmarks

// MARK: - Entry Point

let benchmarks: @Sendable () -> Void = {
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
