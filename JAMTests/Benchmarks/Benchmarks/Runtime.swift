import Benchmark
import Blockchain
import Foundation
import Utils

func runtimeBenchmarks() {
    Benchmark.defaultConfiguration.timeUnits = BenchmarkTimeUnits.microseconds

    // MARK: - Setup helpers

    func createGenesis(config: ProtocolConfigRef) async throws -> (BlockRef, StateRef) {
        let (state, block) = try State.devGenesis(config: config)
        // Save the state to persist layer changes to the backend
        _ = try await state.value.save()
        return (block, state)
    }

    // Use a simple config for benchmarking
    let config = ProtocolConfigRef.tiny

    // MARK: - Runtime initialization

    Benchmark("runtime.init", configuration: BokaBenchmark.scaledNano) { benchmark in
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            let runtime = Runtime(config: config, ancestry: nil)
            blackHole(runtime)
        }
        benchmark.stopMeasurement()
    }

    // MARK: - Runtime.validate operations (validation only, no apply)

    Benchmark("runtime.validate.header") { benchmark in
        let (parentBlock, parentState) = try await createGenesis(config: config)
        let stateRoot = await parentState.value.stateRoot
        // Create a block with the correct priorStateRoot and extrinsicsHash
        let block = BlockRef.dummy(config: config, parent: parentBlock).mutate { b in
            b.header.unsigned.priorStateRoot = stateRoot
            b.header.unsigned.extrinsicsHash = b.extrinsic.hash()
        }
        let runtime = Runtime(config: config, ancestry: nil)
        let validatedBlock = try block.toValidated(config: config)
        let context = Runtime.ApplyContext(timeslot: block.header.timeslot, stateRoot: stateRoot)

        benchmark.startMeasurement()
        try runtime.validateHeader(block: validatedBlock, state: parentState, context: context)
        benchmark.stopMeasurement()
    }

    Benchmark("runtime.validate.block") { benchmark in
        let (parentBlock, parentState) = try await createGenesis(config: config)
        let stateRoot = await parentState.value.stateRoot
        // Create a block with the correct priorStateRoot and extrinsicsHash
        let block = BlockRef.dummy(config: config, parent: parentBlock).mutate { b in
            b.header.unsigned.priorStateRoot = stateRoot
            b.header.unsigned.extrinsicsHash = b.extrinsic.hash()
        }
        let runtime = Runtime(config: config, ancestry: nil)
        let validatedBlock = try block.toValidated(config: config)
        let context = Runtime.ApplyContext(timeslot: block.header.timeslot, stateRoot: stateRoot)

        benchmark.startMeasurement()
        try await runtime.validate(block: validatedBlock, state: parentState, context: context)
        benchmark.stopMeasurement()
    }

    // MARK: - State operations (state root computation)

    Benchmark("runtime.state.root.computation", configuration: BokaBenchmark.milliseconds) { benchmark in
        let (_, parentState) = try await createGenesis(config: config)

        benchmark.startMeasurement()
        let root = await parentState.value.stateRoot
        benchmark.stopMeasurement()
        blackHole(root)
    }

    Benchmark("runtime.state.root.batch") { benchmark in
        let (_, genesisState) = try await createGenesis(config: config)

        benchmark.startMeasurement()
        // Access stateRoot on the same genesisState instance repeatedly; this measures cached-root access.
        for _ in 0 ..< 100 {
            let root = await genesisState.value.stateRoot
            blackHole(root)
        }
        benchmark.stopMeasurement()
    }

    // MARK: - Block operations

    Benchmark("runtime.block.toValidated", configuration: BokaBenchmark.scaledNano) { benchmark in
        let (parentBlock, _) = try await createGenesis(config: config)
        let block = BlockRef.dummy(config: config, parent: parentBlock)

        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            let validated = try block.toValidated(config: config)
            blackHole(validated)
        }
        benchmark.stopMeasurement()
    }

    Benchmark("runtime.block.toValidated.batch", configuration: BokaBenchmark.milliseconds) { benchmark in
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

    Benchmark("runtime.context.creation", configuration: BokaBenchmark.scaledNano) { benchmark in
        let (parentBlock, parentState) = try await createGenesis(config: config)
        let stateRoot = await parentState.value.stateRoot

        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            let context = Runtime.ApplyContext(timeslot: parentBlock.header.timeslot, stateRoot: stateRoot)
            blackHole(context)
        }
        benchmark.stopMeasurement()
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
