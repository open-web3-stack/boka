import Benchmark
import Codec
import Foundation
import JAMTests
import Utils

func testVectorsBenchmarks() {
    Benchmark.defaultConfiguration.timeUnits = BenchmarkTimeUnits.milliseconds

    // W3F Erasure (full): encode + reconstruct
    struct ErasureCodingTestcase: Codable { let data: Data; let shards: [Data] }
    let erasureCases = (try? TestLoader.getTestcases(path: "erasure/full", extension: "bin")) ?? []
    if erasureCases.isEmpty {
        print(
            "⚠️  Warning: Erasure coding test vectors not found at 'erasure/full'. Skipping w3f.erasure.full.encode+reconstruct benchmark."
        )
    }
    if !erasureCases.isEmpty {
        let config = TestVariants.full.config
        let basicSize = config.value.erasureCodedPieceSize
        let recoveryCount = config.value.totalNumberOfValidators
        let originalCount = basicSize / 2

        // Pre-decode test cases to avoid including decoding time in benchmark
        let decodedCases = erasureCases.compactMap { testcase in
            try? JamDecoder.decode(ErasureCodingTestcase.self, from: testcase.data, withConfig: config)
        }

        Benchmark("w3f.erasure.full.encode+reconstruct") { _ in
            for t in decodedCases {
                if let shards = try? ErasureCoding.chunk(data: t.data, basicSize: basicSize, recoveryCount: recoveryCount) {
                    let typed = shards.enumerated().map { ErasureCoding.Shard(data: $0.element, index: UInt32($0.offset)) }
                    _ = try? ErasureCoding.reconstruct(
                        shards: Array(typed.prefix(originalCount)),
                        basicSize: basicSize,
                        originalCount: originalCount,
                        recoveryCount: recoveryCount
                    )
                }
            }
        }
    }

    // W3F Shuffle
    struct ShuffleTestCase: Codable { let input: Int; let entropy: String; let output: [Int] }
    let shuffleData = try? TestLoader.getFile(path: "shuffle/shuffle_tests", extension: "json")
    let shuffleTests = shuffleData.flatMap { try? JSONDecoder().decode([ShuffleTestCase].self, from: $0) } ?? []
    if shuffleData == nil {
        print("⚠️  Warning: Shuffle test vectors not found at 'shuffle/shuffle_tests.json'. Skipping w3f.shuffle benchmark.")
    } else if shuffleTests.isEmpty {
        print("⚠️  Warning: Shuffle test file found but failed to decode. Skipping w3f.shuffle benchmark.")
    }
    if let data = shuffleData, !shuffleTests.isEmpty {
        // Pre-convert entropy strings to Data32 to avoid hex parsing in benchmark
        let shuffleCasesWithEntropy = shuffleTests.compactMap { test -> (input: Array<Int>, entropy: Data32)? in
            guard let entropy = Data32(fromHexString: test.entropy) else { return nil }
            return (Array(0 ..< test.input), entropy)
        }

        Benchmark("w3f.shuffle", configuration: .init(timeUnits: .microseconds)) { _ in
            // Inner loop: Shuffle operations are very fast (<1µs), so we batch
            // 10 iterations to ensure the measured time dominates overhead.
            // This provides stable measurements while keeping per-operation
            // semantics clear (the Benchmark harness handles repetitions).
            for _ in 0 ..< 10 {
                for (input, entropy) in shuffleCasesWithEntropy {
                    var inputArray = input
                    inputArray.shuffle(randomness: entropy)
                    blackHole(inputArray)
                }
            }
        }
    }

    // Traces
    let tracePaths = [("traces/fallback", 15), ("traces/safrole", 10), ("traces/storage", 5), ("traces/preimages", 5), ("traces/fuzzy", 5)]
    for (path, iterations) in tracePaths {
        guard let traces = try? JamTestnet.loadTests(path: path, src: .w3f) else {
            print(
                "⚠️  Warning: Trace files not found at '\(path)'. Skipping w3f.traces.\(path.components(separatedBy: "/").last!) benchmark."
            )
            continue
        }
        Benchmark(
            "w3f.traces.\(path.components(separatedBy: "/").last!)",
        ) { benchmark in
            for _ in 0 ..< iterations {
                for trace in traces {
                    guard let testcase = try? JamTestnet.decodeTestcase(trace) else { continue }
                    benchmark.startMeasurement()
                    let result = try? await JamTestnet.runSTF(testcase)
                    switch result {
                    case let .success(stateRef):
                        let root = await stateRef.value.stateRoot
                        blackHole(root)
                    case .failure:
                        blackHole(trace.description)
                    case .none:
                        blackHole(trace.description)
                    }
                    benchmark.stopMeasurement()
                }
            }
        }
    }
}
