import Benchmark
import Blockchain
import Database
import Foundation
import Utils

enum RocksDBBenchmarkError: Error {
    case failedToGetGenesisState
}

func rocksdbBenchmarks() {
    Benchmark.defaultConfiguration.timeUnits = BenchmarkTimeUnits.milliseconds

    // MARK: - Setup helpers

    func createTempDirectory() throws -> (url: URL, cleanup: () -> Void) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RocksDBBenchmarks")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return (tempDir, {
            do {
                try FileManager.default.removeItem(at: tempDir)
            } catch {
                print("⚠️  Warning: Failed to cleanup temporary directory at \(tempDir.path): \(error)")
            }
        })
    }

    func createGenesis(config: ProtocolConfigRef) async throws -> (BlockRef, StateRef) {
        let (state, block) = try await State.devGenesis(config: config)
        return (block, state)
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

    // Use a simple config for benchmarking
    let config = ProtocolConfigRef.tiny

    // MARK: - RocksDB initialization

    Benchmark("rocksdb.init") { benchmark in
        let tempDir = try createTempDirectory()
        defer { tempDir.cleanup() }

        let (genesisBlock, genesisState) = try await createGenesis(config: config)
        let stateData = try await extractStateData(from: genesisState)

        benchmark.startMeasurement()
        let rocksDB = try await RocksDBBackend(
            path: tempDir.url,
            config: config,
            genesisBlock: genesisBlock,
            genesisStateData: stateData
        )
        benchmark.stopMeasurement()

        blackHole(rocksDB)
    }

    // MARK: - Block write operations

    Benchmark("rocksdb.block.write.single") { benchmark in
        let tempDir = try createTempDirectory()
        defer { tempDir.cleanup() }
        let (genesisBlock, genesisState) = try await createGenesis(config: config)
        let stateData = try await extractStateData(from: genesisState)

        let rocksDB = try await RocksDBBackend(
            path: tempDir.url,
            config: config,
            genesisBlock: genesisBlock,
            genesisStateData: stateData
        )

        let block = BlockRef.dummy(config: config, parent: genesisBlock)

        benchmark.startMeasurement()
        try await rocksDB.add(block: block)
        benchmark.stopMeasurement()
    }

    Benchmark("rocksdb.block.write.batch") { benchmark in
        let tempDir = try createTempDirectory()
        defer { tempDir.cleanup() }
        let (genesisBlock, genesisState) = try await createGenesis(config: config)
        let stateData = try await extractStateData(from: genesisState)

        let rocksDB = try await RocksDBBackend(
            path: tempDir.url,
            config: config,
            genesisBlock: genesisBlock,
            genesisStateData: stateData
        )

        var blocks: [BlockRef] = []
        for _ in 0 ..< 100 {
            let prevBlock = blocks.last ?? genesisBlock
            blocks.append(BlockRef.dummy(config: config, parent: prevBlock))
        }

        benchmark.startMeasurement()
        for block in blocks {
            try await rocksDB.add(block: block)
        }
        benchmark.stopMeasurement()
    }

    // MARK: - State write operations

    Benchmark("rocksdb.state.write.single") { benchmark in
        let tempDir = try createTempDirectory()
        defer { tempDir.cleanup() }
        let (genesisBlock, genesisState) = try await createGenesis(config: config)
        let stateData = try await extractStateData(from: genesisState)

        let rocksDB = try await RocksDBBackend(
            path: tempDir.url,
            config: config,
            genesisBlock: genesisBlock,
            genesisStateData: stateData
        )

        benchmark.startMeasurement()
        try await rocksDB.add(state: genesisState)
        benchmark.stopMeasurement()
    }

    Benchmark("rocksdb.state.write.batch") { benchmark in
        let tempDir = try createTempDirectory()
        defer { tempDir.cleanup() }
        let (genesisBlock, genesisState) = try await createGenesis(config: config)
        let stateData = try await extractStateData(from: genesisState)

        let rocksDB = try await RocksDBBackend(
            path: tempDir.url,
            config: config,
            genesisBlock: genesisBlock,
            genesisStateData: stateData
        )

        // Create dummy states (just for benchmarking I/O)
        var states: [StateRef] = []
        for _ in 0 ..< 100 {
            states.append(genesisState)
        }

        benchmark.startMeasurement()
        for state in states {
            try await rocksDB.add(state: state)
        }
        benchmark.stopMeasurement()
    }

    // MARK: - Block read operations

    Benchmark("rocksdb.block.read.single") { benchmark in
        let tempDir = try createTempDirectory()
        defer { tempDir.cleanup() }
        let (genesisBlock, genesisState) = try await createGenesis(config: config)
        let stateData = try await extractStateData(from: genesisState)

        let rocksDB = try await RocksDBBackend(
            path: tempDir.url,
            config: config,
            genesisBlock: genesisBlock,
            genesisStateData: stateData
        )

        benchmark.startMeasurement()
        let block = try await rocksDB.getBlock(hash: genesisBlock.hash)
        benchmark.stopMeasurement()
        blackHole(block)
    }

    Benchmark("rocksdb.block.read.batch") { benchmark in
        let tempDir = try createTempDirectory()
        defer { tempDir.cleanup() }
        let (genesisBlock, genesisState) = try await createGenesis(config: config)
        let stateData = try await extractStateData(from: genesisState)

        let rocksDB = try await RocksDBBackend(
            path: tempDir.url,
            config: config,
            genesisBlock: genesisBlock,
            genesisStateData: stateData
        )

        // Add some blocks
        var blocks: [BlockRef] = []
        for _ in 0 ..< 100 {
            let prevBlock = blocks.last ?? genesisBlock
            let block = BlockRef.dummy(config: config, parent: prevBlock)
            blocks.append(block)
            try await rocksDB.add(block: block)
        }

        benchmark.startMeasurement()
        // Read all blocks
        for block in blocks {
            let readBlock = try await rocksDB.getBlock(hash: block.hash)
            blackHole(readBlock)
        }
        benchmark.stopMeasurement()
    }

    // MARK: - State read operations

    Benchmark("rocksdb.state.read.single") { benchmark in
        let tempDir = try createTempDirectory()
        defer { tempDir.cleanup() }
        let (genesisBlock, genesisState) = try await createGenesis(config: config)
        let stateData = try await extractStateData(from: genesisState)

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

    Benchmark("rocksdb.state.read.batch") { benchmark in
        let tempDir = try createTempDirectory()
        defer { tempDir.cleanup() }
        let (genesisBlock, genesisState) = try await createGenesis(config: config)
        let stateData = try await extractStateData(from: genesisState)

        let rocksDB = try await RocksDBBackend(
            path: tempDir.url,
            config: config,
            genesisBlock: genesisBlock,
            genesisStateData: stateData
        )

        // Add some states
        for _ in 0 ..< 100 {
            try await rocksDB.add(state: genesisState)
        }

        benchmark.startMeasurement()
        // Read states - reads the same state 100 times, measuring RocksDB's hot cache performance
        // rather than disk I/O or throughput for different states
        for _ in 0 ..< 100 {
            let state = try await rocksDB.getState(hash: genesisBlock.hash)
            blackHole(state)
        }
        benchmark.stopMeasurement()
    }

    // MARK: - GetKeys operations

    Benchmark("rocksdb.getkeys.prefix") { benchmark in
        let tempDir = try createTempDirectory()
        defer { tempDir.cleanup() }
        let (genesisBlock, genesisState) = try await createGenesis(config: config)

        // Create state with some test data that shares a common prefix
        var stateData: [Data31: Data] = [:]
        for i in 0 ..< 100 {
            // Create 31-byte keys with common prefix (0x00) + varying second byte
            // This allows proper prefix scanning benchmarking
            let data = Data([0x00, UInt8(i)] + Data(repeating: 0, count: 29))
            if let key = Data31(data) {
                let value = Data([UInt8(i), UInt8(i + 1), UInt8(i + 2)])
                stateData[key] = value
            }
        }

        let rocksDB = try await RocksDBBackend(
            path: tempDir.url,
            config: config,
            genesisBlock: genesisBlock,
            genesisStateData: stateData
        )

        benchmark.startMeasurement()
        let results = try await rocksDB.getKeys(prefix: Data([0x00]), count: 100, startKey: nil, blockHash: genesisBlock.hash)
        benchmark.stopMeasurement()
        blackHole(results)
    }

    Benchmark("rocksdb.getkeys.all") { benchmark in
        let tempDir = try createTempDirectory()
        defer { tempDir.cleanup() }
        let (genesisBlock, genesisState) = try await createGenesis(config: config)
        let stateData = try await extractStateData(from: genesisState)

        let rocksDB = try await RocksDBBackend(
            path: tempDir.url,
            config: config,
            genesisBlock: genesisBlock,
            genesisStateData: stateData
        )

        benchmark.startMeasurement()
        let results = try await rocksDB.getKeys(prefix: Data(), count: UInt32.max, startKey: nil, blockHash: genesisBlock.hash)
        benchmark.stopMeasurement()
        blackHole(results)
    }

    // MARK: - State root computation through RocksDB

    Benchmark("rocksdb.stateroot.computation") { benchmark in
        let tempDir = try createTempDirectory()
        defer { tempDir.cleanup() }
        let (genesisBlock, genesisState) = try await createGenesis(config: config)
        let stateData = try await extractStateData(from: genesisState)

        let rocksDB = try await RocksDBBackend(
            path: tempDir.url,
            config: config,
            genesisBlock: genesisBlock,
            genesisStateData: stateData
        )

        benchmark.startMeasurement()
        let state = try await rocksDB.getState(hash: genesisBlock.hash)
        guard let state else {
            throw RocksDBBenchmarkError.failedToGetGenesisState
        }
        let root = await state.value.stateRoot
        benchmark.stopMeasurement()
        blackHole(root)
    }
}
