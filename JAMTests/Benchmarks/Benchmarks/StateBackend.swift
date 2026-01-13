import Benchmark
import Blockchain
import Foundation
import Utils

func stateBackendBenchmarks() {
    Benchmark.defaultConfiguration.timeUnits = BenchmarkTimeUnits.microseconds

    // MARK: - Setup helpers

    func createTestData(count: Int) -> [(key: Data31, value: Data)] {
        (0 ..< count).map { i in
            let data = Data([UInt8(i % 256), UInt8((i / 256) % 256), UInt8((i / 65536) % 256)])
            return (key: Data31(data.blake2b256hash().data[relative: 0 ..< 31])!, value: data + Data(repeating: UInt8(i % 256), count: 32))
        }
    }

    func createTestDataWithSharedPrefix(count: Int, prefix: UInt8 = 0x00) -> [(key: Data31, value: Data)] {
        (0 ..< count).map { i in
            // Create keys with a shared prefix byte for prefix iteration benchmarking
            let keyData = Data([prefix] + [UInt8(i % 256), UInt8((i / 256) % 256)] + Data(repeating: 0, count: 28))
            let valueData = Data([UInt8(i % 256), UInt8((i / 256) % 256), UInt8((i / 65536) % 256)])
            return (key: Data31(keyData)!, value: valueData + Data(repeating: UInt8(i % 256), count: 32))
        }
    }

    // MARK: - Trie Node Operations

    Benchmark("statebackend.get.node.hit") { benchmark in
        let backend = InMemoryBackend()
        let trie = StateTrie(rootHash: Data32(), backend: backend)
        let testData = createTestData(count: 100)
        try await trie.update(testData)
        try await trie.save()

        // Get a node hash that exists
        let root = await trie.rootHash

        benchmark.startMeasurement()
        let result = try await backend.read(key: root.data.suffix(31))
        benchmark.stopMeasurement()
        blackHole(result)
    }

    Benchmark("statebackend.get.node.miss") { benchmark in
        let backend = InMemoryBackend()
        let trie = StateTrie(rootHash: Data32(), backend: backend)
        let testData = createTestData(count: 100)
        try await trie.update(testData)
        try await trie.save()

        let randomKey = Data31.random()

        benchmark.startMeasurement()
        let result = try await backend.read(key: randomKey.data)
        benchmark.stopMeasurement()
        blackHole(result)
    }

    Benchmark("statebackend.get.batch", configuration: .init(timeUnits: .milliseconds)) { benchmark in
        let backend = InMemoryBackend()
        let trie = StateTrie(rootHash: Data32(), backend: backend)
        let testData = createTestData(count: 1000)
        try await trie.update(testData)
        try await trie.save()

        // Collect node keys from trie
        let root = await trie.rootHash
        var nodeKeys: [Data] = []
        nodeKeys.append(root.data.suffix(31))

        benchmark.startMeasurement()
        var results: [Data?] = []
        for key in nodeKeys {
            let result = try await backend.read(key: key)
            results.append(result)
        }
        benchmark.stopMeasurement()
        blackHole(results)
    }

    // MARK: - Put Operations

    Benchmark("statebackend.put.node") { benchmark in
        let backend = InMemoryBackend()
        let trie = StateTrie(rootHash: Data32(), backend: backend)
        let testData = createTestData(count: 1)

        benchmark.startMeasurement()
        try await trie.update(testData)
        try await trie.save()
        benchmark.stopMeasurement()
    }

    Benchmark("statebackend.put.batch", configuration: .init(timeUnits: .milliseconds)) { benchmark in
        let backend = InMemoryBackend()
        let trie = StateTrie(rootHash: Data32(), backend: backend)
        let testData = createTestData(count: 1000)

        benchmark.startMeasurement()
        try await trie.update(testData)
        try await trie.save()
        benchmark.stopMeasurement()
    }

    // MARK: - Cache Operations

    Benchmark("statebackend.cache.hit") { benchmark in
        let backend = InMemoryBackend()
        let trie = StateTrie(rootHash: Data32(), backend: backend)
        let testData = createTestData(count: 100)
        try await trie.update(testData)
        try await trie.save()

        // Read the same key multiple times (cache hits in trie's node cache)
        benchmark.startMeasurement()
        var results: [Data?] = []
        for _ in 0 ..< 100 {
            let result = try await trie.read(key: testData[50].key)
            results.append(result)
        }
        benchmark.stopMeasurement()
        blackHole(results)
    }

    Benchmark("statebackend.cache.miss") { benchmark in
        let backend = InMemoryBackend()
        let trie = StateTrie(rootHash: Data32(), backend: backend)
        let testData = createTestData(count: 100)
        try await trie.update(testData)
        try await trie.save()

        benchmark.startMeasurement()
        // Read different keys each time (cache misses)
        var results: [Data?] = []
        for data in testData {
            let result = try await trie.read(key: data.key)
            results.append(result)
        }
        benchmark.stopMeasurement()
        blackHole(results)
    }

    // MARK: - Storage Query Operations

    Benchmark("statebackend.storage.query") { benchmark in
        let backend = InMemoryBackend()
        let trie = StateTrie(rootHash: Data32(), backend: backend)
        let testData = createTestData(count: 100)
        try await trie.update(testData)
        try await trie.save()

        benchmark.startMeasurement()
        let result = try await trie.read(key: testData[50].key)
        benchmark.stopMeasurement()
        blackHole(result)
    }

    Benchmark("statebackend.storage.prefix", configuration: .init(timeUnits: .milliseconds)) { benchmark in
        let backend = InMemoryBackend()
        let trie = StateTrie(rootHash: Data32(), backend: backend)
        let testData = createTestDataWithSharedPrefix(count: 1000)
        try await trie.update(testData)
        try await trie.save()

        // Use prefix that matches all keys (first byte is 0x00 for all keys)
        let prefix = Data([0x00])

        benchmark.startMeasurement()
        let results = try await trie.getKeys(matchingPrefix: prefix, bitsCount: 8)
        benchmark.stopMeasurement()
        blackHole(results)
    }

    // MARK: - State Backend Read/Write Operations

    Benchmark("statebackend.read.single") { benchmark in
        let backend = InMemoryBackend()
        let stateBackend = StateBackend(backend, config: ProtocolConfigRef.dev, rootHash: Data32())
        let testData = createTestData(count: 1)
        try await stateBackend.writeRaw(testData)

        benchmark.startMeasurement()
        let result = try await stateBackend.readRaw(testData[0].key)
        benchmark.stopMeasurement()
        blackHole(result)
    }

    Benchmark("statebackend.write.single") { benchmark in
        let backend = InMemoryBackend()
        let stateBackend = StateBackend(backend, config: ProtocolConfigRef.dev, rootHash: Data32())
        let testData = createTestData(count: 1)

        benchmark.startMeasurement()
        try await stateBackend.writeRaw(testData)
        benchmark.stopMeasurement()
    }

    Benchmark("statebackend.write.batch", configuration: .init(timeUnits: .milliseconds)) { benchmark in
        let backend = InMemoryBackend()
        let stateBackend = StateBackend(backend, config: ProtocolConfigRef.dev, rootHash: Data32())
        let testData = createTestData(count: 1000)

        benchmark.startMeasurement()
        try await stateBackend.writeRaw(testData)
        benchmark.stopMeasurement()
    }

    // MARK: - Get Keys with Prefix/StartKey/Limit

    Benchmark("statebackend.getkeys.prefix") { benchmark in
        let backend = InMemoryBackend()
        let stateBackend = StateBackend(backend, config: ProtocolConfigRef.dev, rootHash: Data32())
        let testData = createTestDataWithSharedPrefix(count: 1000)
        try await stateBackend.writeRaw(testData)

        // Use prefix that matches all keys (first byte is 0x00)
        let prefix = Data([0x00])

        benchmark.startMeasurement()
        let results = try await stateBackend.getKeys(prefix, nil, nil)
        benchmark.stopMeasurement()
        blackHole(results)
    }

    Benchmark("statebackend.getkeys.startkey") { benchmark in
        let backend = InMemoryBackend()
        let stateBackend = StateBackend(backend, config: ProtocolConfigRef.dev, rootHash: Data32())
        let testData = createTestData(count: 1000)
        try await stateBackend.writeRaw(testData)

        benchmark.startMeasurement()
        let results = try await stateBackend.getKeys(nil, testData[100].key, nil)
        benchmark.stopMeasurement()
        blackHole(results)
    }

    Benchmark("statebackend.getkeys.limit") { benchmark in
        let backend = InMemoryBackend()
        let stateBackend = StateBackend(backend, config: ProtocolConfigRef.dev, rootHash: Data32())
        let testData = createTestData(count: 1000)
        try await stateBackend.writeRaw(testData)

        benchmark.startMeasurement()
        let results = try await stateBackend.getKeys(nil, nil, 100)
        benchmark.stopMeasurement()
        blackHole(results)
    }

    Benchmark("statebackend.getkeys.complex", configuration: .init(timeUnits: .milliseconds)) { benchmark in
        let backend = InMemoryBackend()
        let stateBackend = StateBackend(backend, config: ProtocolConfigRef.dev, rootHash: Data32())
        let testData = createTestDataWithSharedPrefix(count: 1000)
        try await stateBackend.writeRaw(testData)

        // Use prefix that matches all keys (first byte is 0x00)
        let prefix = Data([0x00])
        let startKey = testData[100].key
        let limit: UInt32 = 100

        benchmark.startMeasurement()
        let results = try await stateBackend.getKeys(prefix, startKey, limit)
        benchmark.stopMeasurement()
        blackHole(results)
    }

    // MARK: - Batch Update Operations

    Benchmark("statebackend.batchupdate.write") { benchmark in
        let backend = InMemoryBackend()
        let testData = createTestData(count: 100)
        let ops: [StateBackendOperation] = testData.map { .write(key: $0.key.data, value: $0.value) }

        benchmark.startMeasurement()
        try await backend.batchUpdate(ops)
        benchmark.stopMeasurement()
    }

    Benchmark("statebackend.batchupdate.mixed", configuration: .init(timeUnits: .milliseconds)) { benchmark in
        let backend = InMemoryBackend()
        let testData = createTestData(count: 1000)

        // Create mixed operations: writes, ref increments, ref decrements
        var ops: [StateBackendOperation] = []
        for data in testData {
            ops.append(.write(key: data.key.data, value: data.value))
            ops.append(.refIncrement(key: data.key.data))
        }

        benchmark.startMeasurement()
        try await backend.batchUpdate(ops)
        benchmark.stopMeasurement()
    }
}
