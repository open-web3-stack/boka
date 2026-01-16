import Benchmark
import Blockchain
import Database
import Foundation
import Utils

/// Detailed profiling benchmarks for RocksDB performance investigation
/// Focuses on understanding the high p99 values in state read operations
func rocksdbProfilingBenchmarks() {
    Benchmark.defaultConfiguration.timeUnits = BenchmarkTimeUnits.microseconds

    // MARK: - Setup helpers

    func createTempDirectory() throws -> (url: URL, cleanup: () -> Void) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RocksDBProfiling")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return (tempDir, {
            try? FileManager.default.removeItem(at: tempDir)
        })
    }

    func createGenesis(config: ProtocolConfigRef) async throws -> (BlockRef, StateRef, [Data31: Data]) {
        let (state, block) = try State.devGenesis(config: config)
        _ = try await state.value.save()
        let stateData = try await extractStateData(from: state)
        return (block, state, stateData)
    }

    func extractStateData(from state: StateRef) async throws -> [Data31: Data] {
        var stateData: [Data31: Data] = [:]
        let keysValues = try await state.value.backend.getKeys(nil, nil, nil)
        for kv in keysValues {
            if let key = Data31(kv.key) {
                stateData[key] = kv.value
            }
        }
        return stateData
    }

    let config = ProtocolConfigRef.tiny

    // MARK: - Profiling: Cache Hit vs Miss Analysis

    Benchmark("rocksdb.profile.cache.hit") { benchmark in
        let tempDir = try createTempDirectory()
        defer { tempDir.cleanup() }

        let (genesisBlock, _, stateData) = try await createGenesis(config: config)

        let rocksDB = try await RocksDBBackend(
            path: tempDir.url,
            config: config,
            genesisBlock: genesisBlock,
            genesisStateData: stateData
        )

        // Warm up cache by reading once
        _ = try await rocksDB.getState(hash: genesisBlock.hash)

        benchmark.startMeasurement()
        // Measure cache hit performance
        for _ in 0 ..< 1000 {
            let state = try await rocksDB.getState(hash: genesisBlock.hash)
            blackHole(state)
        }
        benchmark.stopMeasurement()
    }

    Benchmark("rocksdb.profile.cache.miss") { benchmark in
        let tempDir = try createTempDirectory()
        defer { tempDir.cleanup() }

        let (genesisBlock, genesisState, stateData) = try await createGenesis(config: config)

        let rocksDB = try await RocksDBBackend(
            path: tempDir.url,
            config: config,
            genesisBlock: genesisBlock,
            genesisStateData: stateData
        )

        // Create multiple blocks with unique states to test cache misses
        var blocks: [BlockRef] = []

        for _ in 0 ..< 100 {
            let prevBlock = blocks.last ?? genesisBlock
            let block = BlockRef.dummy(config: config, parent: prevBlock)
            blocks.append(block)
            try await rocksDB.add(block: block)

            // Create a unique state for this block
            let state = StateRef.dummy(config: config, block: block)
            try await rocksDB.add(state: state)
        }

        benchmark.startMeasurement()
        // Read different states (cache misses)
        for block in blocks {
            _ = try await rocksDB.getState(hash: block.hash)
        }
        benchmark.stopMeasurement()
    }

    // MARK: - Profiling: Read Amplification Analysis

    Benchmark("rocksdb.profile.read.single.key") { benchmark in
        let tempDir = try createTempDirectory()
        defer { tempDir.cleanup() }

        let (genesisBlock, _, stateData) = try await createGenesis(config: config)

        let rocksDB = try await RocksDBBackend(
            path: tempDir.url,
            config: config,
            genesisBlock: genesisBlock,
            genesisStateData: stateData
        )

        benchmark.startMeasurement()
        let state = try await rocksDB.getState(hash: genesisBlock.hash)
        benchmark.stopMeasurement()
        blackHole(state)
    }

    Benchmark("rocksdb.profile.read.trie.nodes") { benchmark in
        let tempDir = try createTempDirectory()
        defer { tempDir.cleanup() }

        let (genesisBlock, genesisState, stateData) = try await createGenesis(config: config)

        let rocksDB = try await RocksDBBackend(
            path: tempDir.url,
            config: config,
            genesisBlock: genesisBlock,
            genesisStateData: stateData
        )

        // Get all trie keys
        let keysValues = try await genesisState.value.backend.getKeys(nil, nil, nil)
        let keys = keysValues.map(\.key)

        benchmark.startMeasurement()
        // Read all trie nodes individually
        for key in keys {
            _ = try await rocksDB.read(key: key)
        }
        benchmark.stopMeasurement()
    }

    Benchmark("rocksdb.profile.read.trie.nodes.batch") { benchmark in
        let tempDir = try createTempDirectory()
        defer { tempDir.cleanup() }

        let (genesisBlock, genesisState, stateData) = try await createGenesis(config: config)

        let rocksDB = try await RocksDBBackend(
            path: tempDir.url,
            config: config,
            genesisBlock: genesisBlock,
            genesisStateData: stateData
        )

        // Get all trie keys
        let keysValues = try await genesisState.value.backend.getKeys(nil, nil, nil)
        let keys = keysValues.map(\.key)

        benchmark.startMeasurement()
        // Read all trie nodes in batch
        _ = try await rocksDB.batchRead(keys: keys)
        benchmark.stopMeasurement()
    }

    // MARK: - Profiling: State Root Computation Breakdown

    Benchmark("rocksdb.profile.stateroot.trie.traversal") { benchmark in
        let tempDir = try createTempDirectory()
        defer { tempDir.cleanup() }

        let (genesisBlock, _, stateData) = try await createGenesis(config: config)

        let rocksDB = try await RocksDBBackend(
            path: tempDir.url,
            config: config,
            genesisBlock: genesisBlock,
            genesisStateData: stateData
        )

        benchmark.startMeasurement()
        let state = try await rocksDB.getState(hash: genesisBlock.hash)
        guard let state else { return }
        let root = await state.value.stateRoot
        benchmark.stopMeasurement()
        blackHole(root)
    }

    Benchmark("rocksdb.profile.stateroot.hash.computation") { benchmark in
        let (genesisBlock, genesisState, _) = try await createGenesis(config: config)

        benchmark.startMeasurement()
        // Just compute hash without database reads (in-memory baseline)
        let root = await genesisState.value.stateRoot
        benchmark.stopMeasurement()
        blackHole(root)
    }

    // MARK: - Profiling: Trie Depth Impact

    Benchmark("rocksdb.profile.trie.shallow") { benchmark in
        let tempDir = try createTempDirectory()
        defer { tempDir.cleanup() }

        let (genesisBlock, genesisState, stateData) = try await createGenesis(config: config)

        let rocksDB = try await RocksDBBackend(
            path: tempDir.url,
            config: config,
            genesisBlock: genesisBlock,
            genesisStateData: stateData
        )

        // Get a shallow key (few hops)
        let keysValues = try await genesisState.value.backend.getKeys(nil, nil, nil)
        guard let firstKey = keysValues.first?.key else { return }

        benchmark.startMeasurement()
        _ = try await rocksDB.read(key: firstKey)
        benchmark.stopMeasurement()
    }

    Benchmark("rocksdb.profile.trie.deep") { benchmark in
        let tempDir = try createTempDirectory()
        defer { tempDir.cleanup() }

        let (genesisBlock, genesisState, stateData) = try await createGenesis(config: config)

        let rocksDB = try await RocksDBBackend(
            path: tempDir.url,
            config: config,
            genesisBlock: genesisBlock,
            genesisStateData: stateData
        )

        // Get a deep key (many hops) - use last key which likely has longer path
        let keysValues = try await genesisState.value.backend.getKeys(nil, nil, nil)
        guard let lastKey = keysValues.last?.key else { return }

        benchmark.startMeasurement()
        _ = try await rocksDB.read(key: lastKey)
        benchmark.stopMeasurement()
    }

    // MARK: - Profiling: Concurrent Read Impact

    Benchmark("rocksdb.profile.concurrent.reads") { benchmark in
        let tempDir = try createTempDirectory()
        defer { tempDir.cleanup() }

        let (genesisBlock, _, stateData) = try await createGenesis(config: config)

        let rocksDB = try await RocksDBBackend(
            path: tempDir.url,
            config: config,
            genesisBlock: genesisBlock,
            genesisStateData: stateData
        )

        benchmark.startMeasurement()
        // Simulate concurrent reads
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 10 {
                group.addTask {
                    for _ in 0 ..< 10 {
                        _ = try await rocksDB.getState(hash: genesisBlock.hash)
                    }
                }
            }
            try await group.waitForAll()
        }
        benchmark.stopMeasurement()
    }

    // MARK: - Profiling: Memory Allocation Impact

    Benchmark("rocksdb.profile.allocation.overhead") { benchmark in
        let tempDir = try createTempDirectory()
        defer { tempDir.cleanup() }

        let (genesisBlock, _, stateData) = try await createGenesis(config: config)

        let rocksDB = try await RocksDBBackend(
            path: tempDir.url,
            config: config,
            genesisBlock: genesisBlock,
            genesisStateData: stateData
        )

        benchmark.startMeasurement()
        var totalAllocations = 0
        for _ in 0 ..< 100 {
            if try await rocksDB.getState(hash: genesisBlock.hash) != nil {
                totalAllocations += 1 // Count state objects
            }
        }
        benchmark.stopMeasurement()
        blackHole(totalAllocations)
    }
}
