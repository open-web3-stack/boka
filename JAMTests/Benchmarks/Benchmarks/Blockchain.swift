import Benchmark
import Blockchain
import Foundation
import Utils

func blockchainBenchmarks() {
    Benchmark.defaultConfiguration.timeUnits = BenchmarkTimeUnits.microseconds

    // MARK: - Setup helpers

    func createGenesis(config: ProtocolConfigRef) async throws -> (BlockRef, StateRef) {
        let (state, block) = try State.devGenesis(config: config)
        return (block, state)
    }

    func createBlockchain(config _: ProtocolConfigRef, genesisBlock: BlockRef,
                          genesisState: StateRef) async throws -> BlockchainDataProvider
    {
        try await BlockchainDataProvider(InMemoryDataProvider(genesisState: genesisState, genesisBlock: genesisBlock))
    }

    // Use a simple config for benchmarking
    let config = ProtocolConfigRef.tiny

    // MARK: - Blockchain initialization

    Benchmark("blockchain.init") { benchmark in
        let (genesisBlock, genesisState) = try await createGenesis(config: config)

        benchmark.startMeasurement()
        let provider = try await BlockchainDataProvider(InMemoryDataProvider(genesisState: genesisState, genesisBlock: genesisBlock))
        benchmark.stopMeasurement()
        blackHole(provider)
    }

    // MARK: - Block creation

    Benchmark("block.create") { benchmark in
        let (genesisBlock, _) = try await createGenesis(config: config)

        benchmark.startMeasurement()
        let block = BlockRef.dummy(config: config, parent: genesisBlock)
        benchmark.stopMeasurement()
        blackHole(block)
    }

    Benchmark("block.create.batch", configuration: .init(timeUnits: .milliseconds)) { benchmark in
        let (genesisBlock, _) = try await createGenesis(config: config)

        benchmark.startMeasurement()
        var blocks: [BlockRef] = []
        blocks.reserveCapacity(1000)
        for _ in 0 ..< 1000 {
            blocks.append(BlockRef.dummy(config: config, parent: genesisBlock))
        }
        benchmark.stopMeasurement()
        blackHole(blocks)
    }

    // MARK: - Block validation

    Benchmark("block.validate") { benchmark in
        let (genesisBlock, _) = try await createGenesis(config: config)
        let block = BlockRef.dummy(config: config, parent: genesisBlock)

        benchmark.startMeasurement()
        let validated = try block.toValidated(config: config)
        benchmark.stopMeasurement()
        blackHole(validated)
    }

    Benchmark("block.validate.batch", configuration: .init(timeUnits: .milliseconds)) { benchmark in
        let (genesisBlock, _) = try await createGenesis(config: config)
        var blocks: [BlockRef] = []
        blocks.reserveCapacity(100)
        for _ in 0 ..< 100 {
            blocks.append(BlockRef.dummy(config: config, parent: genesisBlock))
        }

        benchmark.startMeasurement()
        for block in blocks {
            let validated = try block.toValidated(config: config)
            blackHole(validated)
        }
        benchmark.stopMeasurement()
    }

    // MARK: - Hash operations

    Benchmark("block.hash.single") { benchmark in
        let (genesisBlock, _) = try await createGenesis(config: config)
        let block = BlockRef.dummy(config: config, parent: genesisBlock)

        benchmark.startMeasurement()
        let hash = block.hash
        benchmark.stopMeasurement()
        blackHole(hash)
    }

    Benchmark("block.hash.batch", configuration: .init(timeUnits: .milliseconds)) { benchmark in
        let (genesisBlock, _) = try await createGenesis(config: config)
        var blocks: [BlockRef] = []
        blocks.reserveCapacity(1000)
        for _ in 0 ..< 1000 {
            blocks.append(BlockRef.dummy(config: config, parent: genesisBlock))
        }

        benchmark.startMeasurement()
        for block in blocks {
            blackHole(block.hash)
        }
        benchmark.stopMeasurement()
    }

    // MARK: - Block mutation

    Benchmark("block.mutate") { benchmark in
        let (genesisBlock, _) = try await createGenesis(config: config)
        let block = BlockRef.dummy(config: config, parent: genesisBlock)

        benchmark.startMeasurement()
        let mutated = block.mutate { b in
            b.header.unsigned.timeslot = b.header.timeslot + 1
        }
        benchmark.stopMeasurement()
        blackHole(mutated)
    }

    Benchmark("block.mutate.batch") { benchmark in
        let (genesisBlock, _) = try await createGenesis(config: config)
        var blocks: [BlockRef] = []
        blocks.reserveCapacity(100)
        for _ in 0 ..< 100 {
            blocks.append(BlockRef.dummy(config: config, parent: genesisBlock))
        }

        benchmark.startMeasurement()
        var mutated: [BlockRef] = []
        mutated.reserveCapacity(100)
        for block in blocks {
            mutated.append(block.mutate { b in
                b.header.unsigned.timeslot = b.header.timeslot + 1
            })
        }
        benchmark.stopMeasurement()
        blackHole(mutated)
    }

    // MARK: - State root operations

    Benchmark("blockchain.state.root", configuration: .init(timeUnits: .milliseconds)) { benchmark in
        let (_, genesisState) = try await createGenesis(config: config)

        benchmark.startMeasurement()
        for _ in 0 ..< 100 {
            let root = await genesisState.value.stateRoot
            blackHole(root)
        }
        benchmark.stopMeasurement()
    }

    // MARK: - Chain queries

    Benchmark("blockchain.get.block") { benchmark in
        let (genesisBlock, genesisState) = try await createGenesis(config: config)
        let provider = try await BlockchainDataProvider(InMemoryDataProvider(genesisState: genesisState, genesisBlock: genesisBlock))

        benchmark.startMeasurement()
        let retrievedBlock = try await provider.getBlock(hash: genesisBlock.hash)
        benchmark.stopMeasurement()
        blackHole(retrievedBlock)
    }

    Benchmark("blockchain.get.block.batch") { benchmark in
        let (genesisBlock, genesisState) = try await createGenesis(config: config)
        let provider = try await BlockchainDataProvider(InMemoryDataProvider(genesisState: genesisState, genesisBlock: genesisBlock))

        benchmark.startMeasurement()
        for _ in 0 ..< 100 {
            let block = try await provider.getBlock(hash: genesisBlock.hash)
            blackHole(block)
        }
        benchmark.stopMeasurement()
    }

    // MARK: - Block header operations

    Benchmark("blockchain.get.header") { benchmark in
        let (genesisBlock, genesisState) = try await createGenesis(config: config)
        let provider = try await BlockchainDataProvider(InMemoryDataProvider(genesisState: genesisState, genesisBlock: genesisBlock))

        benchmark.startMeasurement()
        let header = try await provider.getHeader(hash: genesisBlock.hash)
        benchmark.stopMeasurement()
        blackHole(header)
    }

    Benchmark("blockchain.get.header.batch") { benchmark in
        let (genesisBlock, genesisState) = try await createGenesis(config: config)
        let provider = try await BlockchainDataProvider(InMemoryDataProvider(genesisState: genesisState, genesisBlock: genesisBlock))

        benchmark.startMeasurement()
        for _ in 0 ..< 100 {
            let header = try await provider.getHeader(hash: genesisBlock.hash)
            blackHole(header)
        }
        benchmark.stopMeasurement()
    }
}
