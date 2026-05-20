import Benchmark

enum BokaBenchmark {
    private static var timePercentiles: BenchmarkThresholds.RelativeThresholds {
        [
            .p25: 5.0,
            .p50: 5.0,
            .p75: 10.0,
            .p90: 10.0,
            .p99: 20.0,
        ]
    }

    private static var ioPercentiles: BenchmarkThresholds.RelativeThresholds {
        [
            .p25: 10.0,
            .p50: 10.0,
            .p75: 15.0,
            .p90: 20.0,
            .p99: 30.0,
        ]
    }

    private static var allocationThresholds: BenchmarkThresholds {
        BenchmarkThresholds(
            relative: [
                .p50: 10.0,
                .p75: 15.0,
                .p90: 20.0,
            ],
            absolute: [
                .p50: 10,
                .p75: 10,
                .p90: 10,
            ]
        )
    }

    private static var timeThresholds: BenchmarkThresholds {
        BenchmarkThresholds(relative: timePercentiles)
    }

    private static var ioThresholds: BenchmarkThresholds {
        BenchmarkThresholds(relative: ioPercentiles)
    }

    static var defaultThresholds: [BenchmarkMetric: BenchmarkThresholds] {
        [
            .wallClock: timeThresholds,
            .throughput: timeThresholds,
            .cpuTotal: timeThresholds,
            .instructions: timeThresholds,
            .mallocCountTotal: allocationThresholds,
            .peakMemoryResident: BenchmarkThresholds(relative: ioPercentiles),
        ]
    }

    static func applyDefaultConfiguration() {
        Benchmark.defaultConfiguration = configuration()
    }

    static func configuration(
        metrics: [BenchmarkMetric] = .default,
        timeUnits: BenchmarkTimeUnits = .microseconds,
        scalingFactor: BenchmarkScalingFactor = .one,
        maxDuration: Duration = .seconds(1),
        maxIterations: Int = 10_000,
        warmupIterations: Int = 2,
        thresholds: [BenchmarkMetric: BenchmarkThresholds]? = defaultThresholds
    ) -> Benchmark.Configuration {
        .init(
            metrics: metrics,
            timeUnits: timeUnits,
            warmupIterations: warmupIterations,
            scalingFactor: scalingFactor,
            maxDuration: maxDuration,
            maxIterations: maxIterations,
            thresholds: thresholds,
        )
    }

    static var scaledNano: Benchmark.Configuration {
        configuration(
            metrics: .microbenchmark,
            timeUnits: .nanoseconds,
            scalingFactor: .kilo,
            thresholds: [
                .wallClock: timeThresholds,
                .throughput: timeThresholds,
            ]
        )
    }

    static var milliseconds: Benchmark.Configuration {
        configuration(timeUnits: .milliseconds, thresholds: [
            .wallClock: ioThresholds,
            .throughput: ioThresholds,
            .cpuTotal: ioThresholds,
            .instructions: ioThresholds,
            .mallocCountTotal: allocationThresholds,
            .peakMemoryResident: BenchmarkThresholds(relative: ioPercentiles),
        ])
    }
}
