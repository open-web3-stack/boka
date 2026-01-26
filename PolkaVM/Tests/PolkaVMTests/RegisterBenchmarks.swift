import Benchmark

// Register all PolkaVM benchmarks
let polkaVMBenchmarks: @Sendable () -> Void = {
    polkaVMBenchmarks()
    polkaVMExecutionModeBenchmarks()
    sandboxPoolBenchmarks()
}
