import Benchmark
import Blockchain
import Codec
import Foundation
import JAMTests
import Utils

private struct TraceBenchmarkCase {
    let testcase: JamTestnetTestcase
    let block: BlockRef
    let validatedBlock: Validated<BlockRef>
}

private struct TraceApplyPreparation {
    let testcase: JamTestnetTestcase
    let block: BlockRef
    let previousState: State
    var state: State
    let previousTimeslot: TimeslotIndex
    let availableReports: [WorkReport]
}

private struct TracePostAccumulationPreparation {
    let testcase: JamTestnetTestcase
    let block: BlockRef
    let previousState: State
    var state: State
    let accumulateRoot: Data32
    let accumulateStats: AccumulationStats
    let availableReports: [WorkReport]
}

private struct TracePrePreimagesPreparation {
    let block: BlockRef
    let previousState: State
    var state: State
    let reporters: [Ed25519PublicKey]
    let availableReports: [WorkReport]
    let accumulateStats: AccumulationStats
}

private struct TracePreSavePreparation {
    let block: BlockRef
    let previousState: State
    var state: State
    let reporters: [Ed25519PublicKey]
    let availableReports: [WorkReport]
    let accumulateStats: AccumulationStats
}

private func decodedTraceCases(path: String, benchmarkName: String, config: ProtocolConfigRef) -> [TraceBenchmarkCase]? {
    guard let traces = try? JamTestnet.loadTests(path: path, src: .w3f) else {
        print("⚠️  Warning: Trace files not found at '\(path)'. Skipping \(benchmarkName) phase benchmarks.")
        return nil
    }

    let cases = traces.compactMap { trace -> TraceBenchmarkCase? in
        guard
            let testcase = try? JamTestnet.decodeTestcase(trace, config: config),
            let validatedBlock = try? testcase.block.asRef().toValidated(config: config)
        else {
            return nil
        }
        return TraceBenchmarkCase(
            testcase: testcase,
            block: testcase.block.asRef(),
            validatedBlock: validatedBlock,
        )
    }

    return cases.isEmpty ? nil : cases
}

private func prepareTraceForAssurances(
    _ trace: TraceBenchmarkCase,
    runtime: Runtime,
    config: ProtocolConfigRef,
) async -> TraceApplyPreparation? {
    guard var state = try? await trace.testcase.preState.toState(config: config) else {
        return nil
    }

    let previousState = state
    let previousTimeslot = state.timeslot

    do {
        try runtime.updateSafrole(block: trace.block, state: &state)
        try runtime.validateHeaderSeal(block: trace.block, state: state)
        try runtime.updateDisputes(block: trace.block, state: &state)
        let availableReports = try await runtime.updateAssurances(block: trace.block, state: &state)
        return TraceApplyPreparation(
            testcase: trace.testcase,
            block: trace.block,
            previousState: previousState,
            state: state,
            previousTimeslot: previousTimeslot,
            availableReports: availableReports,
        )
    } catch {
        return nil
    }
}

private func prepareTraceAfterAccumulation(
    _ trace: TraceBenchmarkCase,
    runtime: Runtime,
    config: ProtocolConfigRef,
) async -> TracePostAccumulationPreparation? {
    guard var prepared = await prepareTraceForAssurances(trace, runtime: runtime, config: config) else {
        return nil
    }

    do {
        let (accumulateRoot, commitments, accumulateStats) = try await prepared.state.update(
            config: config,
            availableReports: prepared.availableReports,
            timeslot: prepared.block.value.header.timeslot,
            prevTimeslot: prepared.previousTimeslot,
            entropy: prepared.state.entropyPool.t0,
        )
        prepared.state.lastAccumulationOutputs = commitments
        prepared.state.recentHistory.updatePartial(parentStateRoot: prepared.block.value.header.priorStateRoot)

        return TracePostAccumulationPreparation(
            testcase: prepared.testcase,
            block: prepared.block,
            previousState: prepared.previousState,
            state: prepared.state,
            accumulateRoot: accumulateRoot,
            accumulateStats: accumulateStats,
            availableReports: prepared.availableReports,
        )
    } catch {
        return nil
    }
}

private func prepareTraceBeforePreimages(
    _ trace: TraceBenchmarkCase,
    runtime: Runtime,
    config: ProtocolConfigRef,
) async -> TracePrePreimagesPreparation? {
    guard var prepared = await prepareTraceAfterAccumulation(trace, runtime: runtime, config: config) else {
        return nil
    }

    do {
        let reporters = try await runtime.updateReports(block: prepared.block, state: &prepared.state)
        try runtime.updateRecentHistory(block: prepared.block, state: &prepared.state, accumulateRoot: prepared.accumulateRoot)

        let authorizationResult = try prepared.state.update(
            config: config,
            timeslot: prepared.block.value.header.timeslot,
            auths: prepared.block.value.extrinsic.reports.guarantees.map {
                (CoreIndex($0.workReport.coreIndex), $0.workReport.authorizerHash)
            },
        )
        prepared.state.mergeWith(postState: authorizationResult)

        return TracePrePreimagesPreparation(
            block: prepared.block,
            previousState: prepared.previousState,
            state: prepared.state,
            reporters: reporters,
            availableReports: prepared.availableReports,
            accumulateStats: prepared.accumulateStats,
        )
    } catch {
        return nil
    }
}

private func prepareTraceBeforeSave(
    _ trace: TraceBenchmarkCase,
    runtime: Runtime,
    config: ProtocolConfigRef,
) async -> TracePreSavePreparation? {
    guard var prepared = await prepareTraceBeforePreimages(trace, runtime: runtime, config: config) else {
        return nil
    }

    do {
        try await runtime.updatePreimages(
            block: prepared.block,
            state: &prepared.state,
            priorState: prepared.previousState,
        )

        return TracePreSavePreparation(
            block: prepared.block,
            previousState: prepared.previousState,
            state: prepared.state,
            reporters: prepared.reporters,
            availableReports: prepared.availableReports,
            accumulateStats: prepared.accumulateStats,
        )
    } catch {
        return nil
    }
}

private func registerTracePhaseBenchmarks(
    name: String,
    path: String,
    config: ProtocolConfigRef,
) {
    guard let traces = decodedTraceCases(path: path, benchmarkName: name, config: config) else {
        return
    }

    Benchmark("w3f.traces.\(name).setupState") { benchmark in
        for trace in traces {
            benchmark.startMeasurement()
            let state = try? await trace.testcase.preState.toState(config: config)
            benchmark.stopMeasurement()

            blackHole(state)
        }
    }

    Benchmark("w3f.traces.\(name).block.toValidated") { benchmark in
        for trace in traces {
            benchmark.startMeasurement()
            let validated = try? trace.block.toValidated(config: config)
            benchmark.stopMeasurement()

            blackHole(validated)
        }
    }

    Benchmark("w3f.traces.\(name).validate") { benchmark in
        let runtime = Runtime(config: config, ancestry: nil)
        for trace in traces {
            guard let stateRef = try? await trace.testcase.preState.toState(config: config).asRef() else {
                continue
            }
            let stateRoot = await stateRef.value.stateRoot
            let context = Runtime.ApplyContext(timeslot: trace.block.value.header.timeslot, stateRoot: stateRoot)

            benchmark.startMeasurement()
            let succeeded: Bool
            do {
                try await runtime.validate(block: trace.validatedBlock, state: stateRef, context: context)
                succeeded = true
            } catch {
                succeeded = false
            }
            benchmark.stopMeasurement()

            blackHole(succeeded)
        }
    }

    Benchmark("w3f.traces.\(name).applyOnly") { benchmark in
        let runtime = Runtime(config: config, ancestry: nil)
        for trace in traces {
            guard let stateRef = try? await trace.testcase.preState.toState(config: config).asRef() else {
                continue
            }

            benchmark.startMeasurement()
            let result = try? await runtime.apply(block: trace.block, state: stateRef)
            benchmark.stopMeasurement()

            blackHole(result)
        }
    }

    Benchmark("w3f.traces.\(name).applyValidated") { benchmark in
        let runtime = Runtime(config: config, ancestry: nil)
        for trace in traces {
            guard let stateRef = try? await trace.testcase.preState.toState(config: config).asRef() else {
                continue
            }

            benchmark.startMeasurement()
            let result = try? await runtime.apply(block: trace.validatedBlock, state: stateRef)
            benchmark.stopMeasurement()

            blackHole(result)
        }
    }

    Benchmark("w3f.traces.\(name).updateSafrole") { benchmark in
        let runtime = Runtime(config: config, ancestry: nil)
        for trace in traces {
            guard var state = try? await trace.testcase.preState.toState(config: config) else {
                continue
            }

            benchmark.startMeasurement()
            let succeeded: Bool
            do {
                try runtime.updateSafrole(block: trace.block, state: &state)
                succeeded = true
            } catch {
                succeeded = false
            }
            benchmark.stopMeasurement()

            blackHole(succeeded)
            blackHole(state.safroleState)
        }
    }

    Benchmark("w3f.traces.\(name).validateHeaderSeal") { benchmark in
        let runtime = Runtime(config: config, ancestry: nil)
        for trace in traces {
            guard var state = try? await trace.testcase.preState.toState(config: config) else {
                continue
            }
            try? runtime.updateSafrole(block: trace.block, state: &state)

            benchmark.startMeasurement()
            let succeeded: Bool
            do {
                try runtime.validateHeaderSeal(block: trace.block, state: state)
                succeeded = true
            } catch {
                succeeded = false
            }
            benchmark.stopMeasurement()

            blackHole(succeeded)
        }
    }

    Benchmark("w3f.traces.\(name).updateDisputes") { benchmark in
        let runtime = Runtime(config: config, ancestry: nil)
        for trace in traces {
            guard var state = try? await trace.testcase.preState.toState(config: config) else {
                continue
            }
            do {
                try runtime.updateSafrole(block: trace.block, state: &state)
                try runtime.validateHeaderSeal(block: trace.block, state: state)
            } catch {
                continue
            }

            benchmark.startMeasurement()
            let succeeded: Bool
            do {
                try runtime.updateDisputes(block: trace.block, state: &state)
                succeeded = true
            } catch {
                succeeded = false
            }
            benchmark.stopMeasurement()

            blackHole(succeeded)
        }
    }

    Benchmark("w3f.traces.\(name).updateAssurances") { benchmark in
        let runtime = Runtime(config: config, ancestry: nil)
        for trace in traces {
            guard var state = try? await trace.testcase.preState.toState(config: config) else {
                continue
            }
            do {
                try runtime.updateSafrole(block: trace.block, state: &state)
                try runtime.validateHeaderSeal(block: trace.block, state: state)
                try runtime.updateDisputes(block: trace.block, state: &state)
            } catch {
                continue
            }

            benchmark.startMeasurement()
            let reports = try? await runtime.updateAssurances(block: trace.block, state: &state)
            benchmark.stopMeasurement()

            blackHole(reports)
        }
    }

    Benchmark("w3f.traces.\(name).accumulate") { benchmark in
        let runtime = Runtime(config: config, ancestry: nil)
        for trace in traces {
            guard var prepared = await prepareTraceForAssurances(trace, runtime: runtime, config: config) else {
                continue
            }

            benchmark.startMeasurement()
            let result = try? await prepared.state.update(
                config: config,
                availableReports: prepared.availableReports,
                timeslot: prepared.block.value.header.timeslot,
                prevTimeslot: prepared.previousTimeslot,
                entropy: prepared.state.entropyPool.t0,
            )
            benchmark.stopMeasurement()

            blackHole(result?.root)
        }
    }

    Benchmark("w3f.traces.\(name).updateReports") { benchmark in
        let runtime = Runtime(config: config, ancestry: nil)
        for trace in traces {
            guard var prepared = await prepareTraceAfterAccumulation(trace, runtime: runtime, config: config) else {
                continue
            }

            benchmark.startMeasurement()
            let reporters = try? await runtime.updateReports(block: prepared.block, state: &prepared.state)
            benchmark.stopMeasurement()

            blackHole(reporters)
        }
    }

    Benchmark("w3f.traces.\(name).updateRecentHistory") { benchmark in
        let runtime = Runtime(config: config, ancestry: nil)
        for trace in traces {
            guard var prepared = await prepareTraceAfterAccumulation(trace, runtime: runtime, config: config) else {
                continue
            }

            benchmark.startMeasurement()
            let succeeded: Bool
            do {
                try runtime.updateRecentHistory(
                    block: prepared.block,
                    state: &prepared.state,
                    accumulateRoot: prepared.accumulateRoot,
                )
                succeeded = true
            } catch {
                succeeded = false
            }
            benchmark.stopMeasurement()

            blackHole(succeeded)
        }
    }

    Benchmark("w3f.traces.\(name).updateAuthorization") { benchmark in
        let runtime = Runtime(config: config, ancestry: nil)
        for trace in traces {
            guard let prepared = await prepareTraceAfterAccumulation(trace, runtime: runtime, config: config) else {
                continue
            }
            let auths = prepared.block.value.extrinsic.reports.guarantees.map {
                (CoreIndex($0.workReport.coreIndex), $0.workReport.authorizerHash)
            }

            benchmark.startMeasurement()
            let result = try? prepared.state.update(
                config: config,
                timeslot: prepared.block.value.header.timeslot,
                auths: auths,
            )
            benchmark.stopMeasurement()

            blackHole(result)
        }
    }

    Benchmark("w3f.traces.\(name).updatePreimages") { benchmark in
        let runtime = Runtime(config: config, ancestry: nil)
        for trace in traces {
            guard var prepared = await prepareTraceBeforePreimages(trace, runtime: runtime, config: config) else {
                continue
            }

            benchmark.startMeasurement()
            let succeeded: Bool
            do {
                try await runtime.updatePreimages(
                    block: prepared.block,
                    state: &prepared.state,
                    priorState: prepared.previousState,
                )
                succeeded = true
            } catch {
                succeeded = false
            }
            benchmark.stopMeasurement()

            blackHole(succeeded)
        }
    }

    Benchmark("w3f.traces.\(name).updateActivityStatistics") { benchmark in
        let runtime = Runtime(config: config, ancestry: nil)
        for trace in traces {
            guard let prepared = await prepareTraceBeforeSave(trace, runtime: runtime, config: config) else {
                continue
            }

            benchmark.startMeasurement()
            let statistics = try? prepared.previousState.update(
                config: config,
                newTimeslot: prepared.block.value.header.timeslot,
                extrinsic: prepared.block.value.extrinsic,
                reporters: prepared.reporters,
                authorIndex: prepared.block.value.header.authorIndex,
                availableReports: prepared.availableReports,
                accumulateStats: prepared.accumulateStats,
                activeValidators: prepared.state.currentValidators,
            )
            benchmark.stopMeasurement()

            blackHole(statistics)
        }
    }

    Benchmark("w3f.traces.\(name).save") { benchmark in
        let runtime = Runtime(config: config, ancestry: nil)
        for trace in traces {
            guard var prepared = await prepareTraceBeforeSave(trace, runtime: runtime, config: config) else {
                continue
            }
            prepared.state.activityStatistics = (try? prepared.previousState.update(
                config: config,
                newTimeslot: prepared.block.value.header.timeslot,
                extrinsic: prepared.block.value.extrinsic,
                reporters: prepared.reporters,
                authorIndex: prepared.block.value.header.authorIndex,
                availableReports: prepared.availableReports,
                accumulateStats: prepared.accumulateStats,
                activeValidators: prepared.state.currentValidators,
            )) ?? prepared.state.activityStatistics

            benchmark.startMeasurement()
            let root = try? await prepared.state.save()
            benchmark.stopMeasurement()

            blackHole(root)
        }
    }
}

func testVectorsBenchmarks() {
    Benchmark.defaultConfiguration.timeUnits = BenchmarkTimeUnits.milliseconds

    // W3F Erasure (full): encode + reconstruct
    struct ErasureCodingTestcase: Codable { let data: Data; let shards: [Data] }
    let erasureCases = (try? TestLoader.getTestcases(path: "erasure/full", extension: "bin")) ?? []
    if erasureCases.isEmpty {
        print(
            "⚠️  Warning: Erasure coding test vectors not found at 'erasure/full'. Skipping w3f.erasure.full.encode+reconstruct benchmark.",
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
                        recoveryCount: recoveryCount,
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
    if shuffleData != nil, !shuffleTests.isEmpty {
        // Pre-convert entropy strings to Data32 to avoid hex parsing in benchmark
        let shuffleCasesWithEntropy = shuffleTests.compactMap { test -> (input: Array<Int>, entropy: Data32)? in
            guard let entropy = Data32(fromHexString: test.entropy) else { return nil }
            return (Array(0 ..< test.input), entropy)
        }

        Benchmark("w3f.shuffle", configuration: BokaBenchmark.scaledNano) { benchmark in
            for _ in benchmark.scaledIterations {
                for (input, entropy) in shuffleCasesWithEntropy {
                    var inputArray = input
                    inputArray.shuffle(randomness: entropy)
                    blackHole(inputArray)
                }
            }
        }
    }

    // Traces
    let tracePaths = [
        ("traces/fallback", 15),
        ("traces/safrole", 10),
        ("traces/storage", 5),
        ("traces/storage_light", 5),
        ("traces/preimages", 5),
        ("traces/fuzzy", 5),
    ]
    for (path, iterations) in tracePaths {
        guard let traces = try? JamTestnet.loadTests(path: path, src: .w3f) else {
            print(
                "⚠️  Warning: Trace files not found at '\(path)'. Skipping w3f.traces.\(path.components(separatedBy: "/").last!) benchmark.",
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

    let tracePhaseConfig = TestVariants.tiny.config
    for traceSuite in ["fallback", "safrole", "storage", "storage_light"] {
        registerTracePhaseBenchmarks(
            name: traceSuite,
            path: "traces/\(traceSuite)",
            config: tracePhaseConfig,
        )
    }
}
