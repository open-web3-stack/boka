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

    Benchmark("block.create", configuration: BokaBenchmark.scaledNano) { benchmark in
        let (genesisBlock, _) = try await createGenesis(config: config)

        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            let block = BlockRef.dummy(config: config, parent: genesisBlock)
            blackHole(block)
        }
        benchmark.stopMeasurement()
    }

    Benchmark("block.create.batch", configuration: BokaBenchmark.milliseconds) { benchmark in
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

    Benchmark("block.validate", configuration: BokaBenchmark.scaledNano) { benchmark in
        let (genesisBlock, _) = try await createGenesis(config: config)
        let block = BlockRef.dummy(config: config, parent: genesisBlock)

        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            let validated = try block.toValidated(config: config)
            blackHole(validated)
        }
        benchmark.stopMeasurement()
    }

    Benchmark("block.validate.batch", configuration: BokaBenchmark.milliseconds) { benchmark in
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

    Benchmark("block.hash.single", configuration: BokaBenchmark.scaledNano) { benchmark in
        let (genesisBlock, _) = try await createGenesis(config: config)
        let block = BlockRef.dummy(config: config, parent: genesisBlock)

        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            let hash = block.hash
            blackHole(hash)
        }
        benchmark.stopMeasurement()
    }

    Benchmark("block.hash.batch", configuration: BokaBenchmark.milliseconds) { benchmark in
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

    Benchmark("block.mutate", configuration: BokaBenchmark.scaledNano) { benchmark in
        let (genesisBlock, _) = try await createGenesis(config: config)
        let block = BlockRef.dummy(config: config, parent: genesisBlock)

        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            let mutated = block.mutate { b in
                b.header.unsigned.timeslot = b.header.timeslot + 1
            }
            blackHole(mutated)
        }
        benchmark.stopMeasurement()
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

    Benchmark("blockchain.state.root", configuration: BokaBenchmark.milliseconds) { benchmark in
        let (_, genesisState) = try await createGenesis(config: config)

        benchmark.startMeasurement()
        for _ in 0 ..< 100 {
            let root = await genesisState.value.stateRoot
            blackHole(root)
        }
        benchmark.stopMeasurement()
    }

    // MARK: - Chain queries

    Benchmark("blockchain.get.block", configuration: BokaBenchmark.scaledNano) { benchmark in
        let (genesisBlock, genesisState) = try await createGenesis(config: config)
        let provider = try await BlockchainDataProvider(InMemoryDataProvider(genesisState: genesisState, genesisBlock: genesisBlock))

        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            let retrievedBlock = try await provider.getBlock(hash: genesisBlock.hash)
            blackHole(retrievedBlock)
        }
        benchmark.stopMeasurement()
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

    Benchmark("blockchain.get.header", configuration: BokaBenchmark.scaledNano) { benchmark in
        let (genesisBlock, genesisState) = try await createGenesis(config: config)
        let provider = try await BlockchainDataProvider(InMemoryDataProvider(genesisState: genesisState, genesisBlock: genesisBlock))

        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            let header = try await provider.getHeader(hash: genesisBlock.hash)
            blackHole(header)
        }
        benchmark.stopMeasurement()
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
