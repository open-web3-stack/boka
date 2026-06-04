import Benchmark
import Blockchain
import Foundation
import Utils

func fuzzingStateCopyBenchmarks() {
    let config = ProtocolConfigRef.tiny
    let storageKeyCounts = [32, 256, 1024, 4096]
    let copyConfiguration = BokaBenchmark.configuration(
        timeUnits: .milliseconds,
        maxDuration: .milliseconds(BokaBenchmark.isCIFastMode ? 100 : 250),
        maxIterations: BokaBenchmark.isCIFastMode ? 3 : 12,
        warmupIterations: 1,
        thresholds: nil,
    )

    func makeStorageKey(_ index: Int) -> Data {
        var data = Data()
        data.reserveCapacity(32)
        withUnsafeBytes(of: UInt64(index).littleEndian) { bytes in
            data.append(contentsOf: bytes)
        }
        data.append(contentsOf: repeatElement(UInt8(truncatingIfNeeded: index >> 8), count: 24))
        return data
    }

    func makeStorageValue(_ index: Int, size: Int = 128) -> Data {
        Data((0 ..< size).map { UInt8(truncatingIfNeeded: index &+ $0) })
    }

    func makeStorageRawValues(count: Int) -> [(key: Data31, value: Data?)] {
        (0 ..< count).map { index in
            let serviceIndex = ServiceIndex(index % 16)
            let key = StateKeys.ServiceAccountStorageKey(
                index: serviceIndex,
                key: makeStorageKey(index),
            ).encode()
            return (key: key, value: makeStorageValue(index))
        }
    }

    func makeState(storageKeyCount: Int) async throws -> State {
        var state = State.dummy(config: config)
        try await state.save()
        try await state.backend.writeRaw(makeStorageRawValues(count: storageKeyCount))
        return try await State(backend: state.backend)
    }

    func deepCloneState(_ state: State) async throws -> State {
        let keyValuePairs = try await state.backend.getKeys(nil, nil, nil)
        let newBackend = StateBackend(InMemoryBackend(), config: config, rootHash: Data32())
        try await newBackend.writeRaw(rawValues(from: keyValuePairs))
        return try await State(backend: newBackend)
    }

    func snapshotCloneState(_ state: State) async throws -> State {
        let newBackend = await state.backend.snapshot()
        return try await State(backend: newBackend)
    }

    func rawValues(from keyValuePairs: [(key: Data, value: Data)]) -> [(key: Data31, value: Data?)] {
        keyValuePairs.map { (key: Data31($0.key)!, value: Optional($0.value)) }
    }

    for count in storageKeyCounts {
        Benchmark("fuzzing.statecopy.scanAllKeys.\(count)", configuration: copyConfiguration) { benchmark in
            let state = try await makeState(storageKeyCount: count)

            benchmark.startMeasurement()
            let keyValuePairs = try await state.backend.getKeys(nil, nil, nil)
            benchmark.stopMeasurement()

            blackHole(keyValuePairs)
        }

        Benchmark("fuzzing.statecopy.rewriteAllKeys.\(count)", configuration: copyConfiguration) { benchmark in
            let sourceState = try await makeState(storageKeyCount: count)
            let keyValuePairs = try await sourceState.backend.getKeys(nil, nil, nil)

            benchmark.startMeasurement()
            let newBackend = StateBackend(InMemoryBackend(), config: config, rootHash: Data32())
            try await newBackend.writeRaw(rawValues(from: keyValuePairs))
            let copiedState = try await State(backend: newBackend)
            benchmark.stopMeasurement()

            blackHole(copiedState)
        }

        Benchmark("fuzzing.statecopy.deepClone.\(count)", configuration: copyConfiguration) { benchmark in
            let state = try await makeState(storageKeyCount: count)

            benchmark.startMeasurement()
            let copiedState = try await deepCloneState(state)
            benchmark.stopMeasurement()

            blackHole(copiedState)
        }

        Benchmark("fuzzing.statecopy.snapshotClone.\(count)", configuration: copyConfiguration) { benchmark in
            let state = try await makeState(storageKeyCount: count)

            benchmark.startMeasurement()
            let copiedState = try await snapshotCloneState(state)
            benchmark.stopMeasurement()

            blackHole(copiedState)
        }
    }

    Benchmark("fuzzing.statecopy.layerCopy.4096", configuration: copyConfiguration) { benchmark in
        let state = try await makeState(storageKeyCount: 4096)

        benchmark.startMeasurement()
        let copiedState = State(copying: state)
        benchmark.stopMeasurement()

        blackHole(copiedState)
    }
}
