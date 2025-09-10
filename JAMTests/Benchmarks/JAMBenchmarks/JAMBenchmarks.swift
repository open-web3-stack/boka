import Benchmark
import Codec
import Foundation
import JAMTests
import Utils

let benchmarks: @Sendable () -> Void = {
    // W3F Erasure (full): encode + reconstruct
    struct ErasureCodingTestcase: Codable { let data: Data; let shards: [Data] }
    let erasureCases = (try? TestLoader.getTestcases(path: "erasure/full", extension: "bin")) ?? []
    if !erasureCases.isEmpty {
        let config = TestVariants.full.config
        let basicSize = config.value.erasureCodedPieceSize
        let recoveryCount = config.value.totalNumberOfValidators
        let originalCount = basicSize / 2
        Benchmark("w3f.erasure.full.encode+reconstruct") { _ in
            for testcase in erasureCases {
                if let t = try? JamDecoder.decode(ErasureCodingTestcase.self, from: testcase.data, withConfig: config),
                   let shards = try? ErasureCoding.chunk(data: t.data, basicSize: basicSize, recoveryCount: recoveryCount)
                {
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
    if let data = try? TestLoader.getFile(path: "shuffle/shuffle_tests", extension: "json"),
       let tests = try? JSONDecoder().decode([ShuffleTestCase].self, from: data),
       !tests.isEmpty
    {
        Benchmark("w3f.shuffle") { _ in
            for test in tests {
                var input = Array(0 ..< test.input)
                if let entropy = Data32(fromHexString: test.entropy) {
                    input.shuffle(randomness: entropy)
                    blackHole(input)
                }
            }
        }
    }

    // Traces
    let tracePaths = ["traces/fallback", "traces/safrole", "traces/storage", "traces/preimages"]
    for path in tracePaths {
        let traces = try! JamTestnet.loadTests(path: path, src: .w3f)
        Benchmark("w3f.traces.\(path.components(separatedBy: "/").last!)") { benchmark in
            for trace in traces {
                let testcase = try! JamTestnet.decodeTestcase(trace)
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
