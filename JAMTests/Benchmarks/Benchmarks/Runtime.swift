import Benchmark
import Blockchain
import Foundation
import Utils

func runtimeBenchmarks() {
    Benchmark.defaultConfiguration.timeUnits = BenchmarkTimeUnits.microseconds

    // MARK: - Setup helpers

    func createGenesis(config: ProtocolConfigRef) async throws -> (BlockRef, StateRef) {
        let (state, block) = try State.devGenesis(config: config)
        return (block, state)
    }

    // Use a simple config for benchmarking
    let config = ProtocolConfigRef.tiny

    // MARK: - Runtime initialization

    Benchmark("runtime.init") { benchmark in
        benchmark.startMeasurement()
        let runtime = Runtime(config: config, ancestry: nil)
        benchmark.stopMeasurement()
        blackHole(runtime)
    }

    // MARK: - Runtime.validate operations (validation only, no apply)

    Benchmark("runtime.validate.header") { benchmark in
        let (parentBlock, parentState) = try await createGenesis(config: config)
        let block = BlockRef.dummy(config: config, parent: parentBlock)
        let runtime = Runtime(config: config, ancestry: nil)
        let validatedBlock = try block.toValidated(config: config)
        let stateRoot = await parentState.value.stateRoot
        let context = Runtime.ApplyContext(timeslot: block.header.timeslot, stateRoot: stateRoot)

        benchmark.startMeasurement()
        try runtime.validateHeader(block: validatedBlock, state: parentState, context: context)
        benchmark.stopMeasurement()
    }

    Benchmark("runtime.validate.block") { benchmark in
        let (parentBlock, parentState) = try await createGenesis(config: config)
        let block = BlockRef.dummy(config: config, parent: parentBlock)
        let runtime = Runtime(config: config, ancestry: nil)
        let validatedBlock = try block.toValidated(config: config)
        let stateRoot = await parentState.value.stateRoot
        let context = Runtime.ApplyContext(timeslot: block.header.timeslot, stateRoot: stateRoot)

        benchmark.startMeasurement()
        try await runtime.validate(block: validatedBlock, state: parentState, context: context)
        benchmark.stopMeasurement()
    }

    // MARK: - State operations (state root computation)

    Benchmark("runtime.state.root.computation", configuration: .init(timeUnits: .milliseconds)) { benchmark in
        let (_, parentState) = try await createGenesis(config: config)

        benchmark.startMeasurement()
        let root = await parentState.value.stateRoot
        benchmark.stopMeasurement()
        blackHole(root)
    }

    Benchmark("runtime.state.root.batch", configuration: .init(timeUnits: .milliseconds)) { benchmark in
        let (_, genesisState) = try await createGenesis(config: config)

        // Create multiple states to benchmark batch state root computation
        benchmark.startMeasurement()
        // Access stateRoot on the same genesisState instance repeatedly
        // If stateRoot is lazy and cached, this measures cache access rather than recomputation
        for _ in 0 ..< 100 {
            let root = await genesisState.value.stateRoot
            blackHole(root)
        }
        benchmark.stopMeasurement()
    }

    // MARK: - Block operations

    Benchmark("runtime.block.toValidated") { benchmark in
        let (parentBlock, _) = try await createGenesis(config: config)
        let block = BlockRef.dummy(config: config, parent: parentBlock)

        benchmark.startMeasurement()
        _ = try block.toValidated(config: config)
        benchmark.stopMeasurement()
    }

    Benchmark("runtime.block.toValidated.batch", configuration: .init(timeUnits: .milliseconds)) { benchmark in
        let (parentBlock, _) = try await createGenesis(config: config)
        var blocks: [BlockRef] = []
        for _ in 0 ..< 100 {
            blocks.append(BlockRef.dummy(config: config, parent: parentBlock))
        }

        benchmark.startMeasurement()
        for block in blocks {
            _ = try block.toValidated(config: config)
        }
        benchmark.stopMeasurement()
    }

    // MARK: - Context operations

    Benchmark("runtime.context.creation") { benchmark in
        let (parentBlock, parentState) = try await createGenesis(config: config)
        let stateRoot = await parentState.value.stateRoot

        benchmark.startMeasurement()
        let context = Runtime.ApplyContext(timeslot: parentBlock.header.timeslot, stateRoot: stateRoot)
        benchmark.stopMeasurement()
        blackHole(context)
    }

    Benchmark("runtime.context.creation.batch") { benchmark in
        let (parentBlock, parentState) = try await createGenesis(config: config)
        let stateRoot = await parentState.value.stateRoot

        benchmark.startMeasurement()
        for _ in 0 ..< 1000 {
            let context = Runtime.ApplyContext(timeslot: parentBlock.header.timeslot, stateRoot: stateRoot)
            blackHole(context)
        }
        benchmark.stopMeasurement()
    }
}
