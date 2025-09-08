import Benchmark
import Blockchain
import Codec
import Foundation
import JAMTests
import Utils

private func w3f(_ path: String, ext: String = "bin") -> [Testcase] {
    (try? JAMBenchSupport.w3fTestcases(at: path, ext: ext)) ?? []
}

let benchmarks: @Sendable () -> Void = {
    // W3F Erasure (full): encode + reconstruct
    struct ErasureCodingTestcase: Codable { let data: Data; let shards: [Data] }
    let erasureCases = w3f("erasure/full")
    if !erasureCases.isEmpty {
        let cfg = TestVariants.full.config
        let basicSize = cfg.value.erasureCodedPieceSize
        let recoveryCount = cfg.value.totalNumberOfValidators
        let originalCount = basicSize / 2
        Benchmark("w3f.erasure.full.encode+reconstruct") { _ in
            for c in erasureCases {
                if let t = try? JamDecoder.decode(ErasureCodingTestcase.self, from: c.data, withConfig: cfg),
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

    // W3F Shuffle (JSON + compute)
    struct ShuffleTestCase: Codable { let input: Int; let entropy: String; let output: [Int] }
    if let data = try? JAMBenchSupport.w3fFile(at: "shuffle/shuffle_tests", ext: "json"),
       let tests = try? JSONDecoder().decode([ShuffleTestCase].self, from: data),
       !tests.isEmpty
    {
        Benchmark("w3f.shuffle") { _ in
            for t in tests {
                var input = Array(0 ..< t.input)
                if let e = Data32(fromHexString: t.entropy) { input.shuffle(randomness: e); blackHole(input) }
            }
        }
    }

    // JamTestnet traces (full): decode + touch roots
    let tracePaths = ["traces/fallback", "traces/safrole", "traces/storage", "traces/preimages"]
    let traces = tracePaths.flatMap { w3f($0) }
    if !traces.isEmpty {
        Benchmark("w3f.jamtestnet.apply.full") { benchmark in
            for _ in benchmark.scaledIterations {
                for c in traces {
                    let tc = try! JamTestnet.decodeTestcase(c, config: TestVariants.full.config)
                    // Run full STF apply and touch resulting state root
                    let result = try? await JamTestnet.runSTF(tc, config: TestVariants.full.config)
                    switch result {
                    case let .success(stateRef):
                        let root = await stateRef.value.stateRoot
                        blackHole(root)
                    default:
                        blackHole(c.description)
                    }
                }
            }
        }
    }

    // RecentHistory STF (full): updatePartial + update
    struct ReportedWorkPackage: Codable { let hash: Data32; let exportsRoot: Data32 }
    struct RecentHistoryInput: Codable {
        let headerHash: Data32; let parentStateRoot: Data32; let accumulateRoot: Data32; let workPackages: [ReportedWorkPackage]
    }
    struct RecentHistoryTestcase: Codable { let input: RecentHistoryInput; let preState: RecentHistory; let postState: RecentHistory }
    let historyCases = w3f("stf/history/full")
    if !historyCases.isEmpty {
        let cfg = TestVariants.full.config
        Benchmark("w3f.history.full.update") { _ in
            for c in historyCases {
                let tc = try! JamDecoder.decode(RecentHistoryTestcase.self, from: c.data, withConfig: cfg)
                var state = tc.preState
                state.updatePartial(parentStateRoot: tc.input.parentStateRoot)
                let lookup = Dictionary(uniqueKeysWithValues: tc.input.workPackages.map { ($0.hash, $0.exportsRoot) })
                state.update(headerHash: tc.input.headerHash, accumulateRoot: tc.input.accumulateRoot, lookup: lookup)
                blackHole(state)
            }
        }
    }
}
