import Benchmark
import Blockchain
import Foundation
import Utils

func merkleTrieBenchmarks() {
    Benchmark.defaultConfiguration.timeUnits = BenchmarkTimeUnits.microseconds

    // MARK: - Setup helpers

    func createTestData(count: Int) -> [(key: Data31, value: Data)] {
        (0 ..< count).map { i in
            let data = Data([UInt8(i % 256), UInt8((i / 256) % 256), UInt8((i / 65536) % 256)])
            return (key: Data31(data.blake2b256hash().data[relative: 0 ..< 31])!, value: data + Data(repeating: UInt8(i % 256), count: 32))
        }
    }

    func createSmallValue() -> Data {
        Data([0x01, 0x02, 0x03]) // Small value for embedded leaf
    }

    func createLargeValue() -> Data {
        Data(repeating: 0xFF, count: 100) // Large value for regular leaf
    }

    // MARK: - Insert Operations

    Benchmark("trie.insert.single") { benchmark in
        let backend = InMemoryBackend()
        let trie = StateTrie(rootHash: Data32(), backend: backend)
        let testData = createTestData(count: 1)

        benchmark.startMeasurement()
        try await trie.update(testData)
        benchmark.stopMeasurement()
    }

    Benchmark("trie.insert.batch", configuration: .init(timeUnits: .milliseconds)) { benchmark in
        let backend = InMemoryBackend()
        let trie = StateTrie(rootHash: Data32(), backend: backend)
        let testData = createTestData(count: 1000)

        benchmark.startMeasurement()
        try await trie.update(testData)
        benchmark.stopMeasurement()
    }

    // MARK: - Update Operations

    Benchmark("trie.update.single") { benchmark in
        let backend = InMemoryBackend()
        var trie = StateTrie(rootHash: Data32(), backend: backend)
        let testData = createTestData(count: 1)
        try await trie.update(testData)
        try await trie.save()

        // Re-create trie with saved root
        let root = await trie.rootHash
        trie = StateTrie(rootHash: root, backend: backend)
        let updatedData = [(key: testData[0].key, value: Data([0xFF, 0xFF, 0xFF]))]

        benchmark.startMeasurement()
        try await trie.update(updatedData)
        benchmark.stopMeasurement()
    }

    Benchmark("trie.update.batch", configuration: .init(timeUnits: .milliseconds)) { benchmark in
        let backend = InMemoryBackend()
        var trie = StateTrie(rootHash: Data32(), backend: backend)
        let testData = createTestData(count: 1000)
        try await trie.update(testData)
        try await trie.save()

        // Re-create trie with saved root
        let root = await trie.rootHash
        trie = StateTrie(rootHash: root, backend: backend)
        let updatedData = testData.map { (key: $0.key, value: Data([0xFF, 0xFF, 0xFF])) }

        benchmark.startMeasurement()
        try await trie.update(updatedData)
        benchmark.stopMeasurement()
    }

    // MARK: - Delete Operations

    Benchmark("trie.delete.single") { benchmark in
        let backend = InMemoryBackend()
        var trie = StateTrie(rootHash: Data32(), backend: backend)
        let testData = createTestData(count: 1)
        try await trie.update(testData)
        try await trie.save()

        // Re-create trie with saved root
        let root = await trie.rootHash
        trie = StateTrie(rootHash: root, backend: backend)
        let deleteData: [(key: Data31, value: Data?)] = [(key: testData[0].key, value: nil)]

        benchmark.startMeasurement()
        try await trie.update(deleteData)
        benchmark.stopMeasurement()
    }

    Benchmark("trie.delete.batch", configuration: .init(timeUnits: .milliseconds)) { benchmark in
        let backend = InMemoryBackend()
        var trie = StateTrie(rootHash: Data32(), backend: backend)
        let testData = createTestData(count: 1000)
        try await trie.update(testData)
        try await trie.save()

        // Re-create trie with saved root
        let root = await trie.rootHash
        trie = StateTrie(rootHash: root, backend: backend)
        let deleteData: [(key: Data31, value: Data?)] = testData.map { (key: $0.key, value: nil) }

        benchmark.startMeasurement()
        try await trie.update(deleteData)
        benchmark.stopMeasurement()
    }

    // MARK: - Read Operations

    Benchmark("trie.get.single") { benchmark in
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

    Benchmark("trie.get.batch", configuration: .init(timeUnits: .milliseconds)) { benchmark in
        let backend = InMemoryBackend()
        let trie = StateTrie(rootHash: Data32(), backend: backend)
        let testData = createTestData(count: 1000)
        try await trie.update(testData)
        try await trie.save()

        benchmark.startMeasurement()
        for data in testData {
            let result = try await trie.read(key: data.key)
            blackHole(result)
        }
        benchmark.stopMeasurement()
    }

    // MARK: - Root Hash Computation

    Benchmark("trie.compute.root", configuration: .init(timeUnits: .milliseconds)) { benchmark in
        let backend = InMemoryBackend()
        let trie = StateTrie(rootHash: Data32(), backend: backend)
        let testData = createTestData(count: 1000)

        benchmark.startMeasurement()
        try await trie.update(testData)
        try await trie.save()
        let root = await trie.rootHash
        benchmark.stopMeasurement()
        blackHole(root)
    }

    Benchmark("trie.compute.root.incremental", configuration: .init(timeUnits: .milliseconds)) { benchmark in
        let backend = InMemoryBackend()
        let trie = StateTrie(rootHash: Data32(), backend: backend)
        let testData = createTestData(count: 100)

        // Initial population
        try await trie.update(testData)
        try await trie.save()

        benchmark.startMeasurement()
        // Incremental updates (like in a real block)
        let updates = testData.prefix(10).map { (key: $0.key, value: Data([0xFF])) }
        try await trie.update(updates)
        try await trie.save()
        let root = await trie.rootHash
        benchmark.stopMeasurement()
        blackHole(root)
    }

    // MARK: - Prefix Iteration

    Benchmark("trie.iterate.prefix", configuration: .init(timeUnits: .milliseconds)) { benchmark in
        let backend = InMemoryBackend()
        let trie = StateTrie(rootHash: Data32(), backend: backend)
        let testData = createTestData(count: 1000)
        try await trie.update(testData)
        try await trie.save()

        // Use a prefix that will match some keys
        let prefix = testData[100].key.data.prefix(8)

        benchmark.startMeasurement()
        let results = try await trie.getKeys(matchingPrefix: prefix, bitsCount: 64)
        benchmark.stopMeasurement()
        blackHole(results)
    }

    // MARK: - Node Encoding/Decoding

    Benchmark("trie.encode.node") { benchmark in
        let backend = InMemoryBackend()
        let trie = StateTrie(rootHash: Data32(), backend: backend)
        let testData = createTestData(count: 100)
        try await trie.update(testData)
        try await trie.save()

        benchmark.startMeasurement()
        // Encoding happens during save - trigger it again
        try await trie.save()
        benchmark.stopMeasurement()
    }

    Benchmark("trie.decode.node") { benchmark in
        let backend = InMemoryBackend()
        var trie = StateTrie(rootHash: Data32(), backend: backend)
        let testData = createTestData(count: 100)
        try await trie.update(testData)
        try await trie.save()

        let root = await trie.rootHash

        // Re-create trie (decodes nodes from backend)
        benchmark.startMeasurement()
        trie = StateTrie(rootHash: root, backend: backend)
        // Force decode by reading
        _ = try await trie.read(key: testData[50].key)
        benchmark.stopMeasurement()
    }

    // MARK: - Value Size Variations

    Benchmark("trie.insert.small") { benchmark in
        let backend = InMemoryBackend()
        let trie = StateTrie(rootHash: Data32(), backend: backend)
        let key = Data31.random()
        let smallValue = createSmallValue()

        benchmark.startMeasurement()
        try await trie.update([(key: key, value: smallValue)])
        benchmark.stopMeasurement()
    }

    Benchmark("trie.insert.large") { benchmark in
        let backend = InMemoryBackend()
        let trie = StateTrie(rootHash: Data32(), backend: backend)
        let key = Data31.random()
        let largeValue = createLargeValue()

        benchmark.startMeasurement()
        try await trie.update([(key: key, value: largeValue)])
        benchmark.stopMeasurement()
    }
}
