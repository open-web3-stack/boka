import Benchmark
import Blockchain
import Foundation
import Utils

func validatorBenchmarks() {
    Benchmark.defaultConfiguration.timeUnits = BenchmarkTimeUnits.milliseconds

    // MARK: - Setup helpers

    func createGenesis(config: ProtocolConfigRef) async throws -> (BlockRef, StateRef) {
        let (state, block) = try State.devGenesis(config: config)
        return (block, state)
    }

    // Use a simple config for benchmarking
    let config = ProtocolConfigRef.tiny

    // MARK: - Block authoring operations

    Benchmark("authoring.build.block") { benchmark in
        let (genesisBlock, _) = try await createGenesis(config: config)
        let parent = genesisBlock

        benchmark.startMeasurement()
        // Build a block with 100 dummy transactions
        var block = BlockRef.dummy(config: config, parent: parent)
        for _ in 0 ..< 100 {
            block = BlockRef.dummy(config: config, parent: parent).mutate { b in
                b.header.unsigned.extrinsicsHash = Data32.random()
            }
        }
        benchmark.stopMeasurement()
        blackHole(block)
    }

    Benchmark("authoring.pre.runtime") { benchmark in
        let (_, genesisState) = try await createGenesis(config: config)

        benchmark.startMeasurement()
        // Prepare data for runtime before block authoring
        let stateRoot = await genesisState.value.stateRoot
        let tickets = ExtrinsicTickets.dummy(config: config)
        let disputes = ExtrinsicDisputes.dummy(config: config)
        let preimages = ExtrinsicPreimages.dummy(config: config)
        let availability = ExtrinsicAvailability.dummy(config: config)
        let guarantees = ExtrinsicGuarantees.dummy(config: config)
        benchmark.stopMeasurement()

        blackHole(stateRoot)
        blackHole(tickets)
        blackHole(disputes)
        blackHole(preimages)
        blackHole(availability)
        blackHole(guarantees)
    }

    Benchmark("authoring.finalize") { benchmark in
        let (genesisBlock, genesisState) = try await createGenesis(config: config)
        let block = BlockRef.dummy(config: config, parent: genesisBlock)

        benchmark.startMeasurement()
        // Simulate finalization by creating block header seal
        let entropy = genesisState.value.entropyPool.t3
        let epoch = block.header.timeslot.timeslotToEpochIndex(config: config)
        blackHole(entropy)
        blackHole(epoch)
        benchmark.stopMeasurement()
    }

    // MARK: - Data operations (baseline for availability chunking)

    Benchmark("data.chunk") { benchmark in
        // Create 1MB of data to chunk
        let data = Data(repeating: 0x42, count: 1_048_576) // 1MB

        benchmark.startMeasurement()
        // Benchmark data slicing (baseline for availability chunking logic)
        let chunkSize = 1024
        var chunks: [Data] = []
        chunks.reserveCapacity(data.count / chunkSize + 1)
        for i in stride(from: 0, to: data.count, by: chunkSize) {
            let end = min(i + chunkSize, data.count)
            chunks.append(Data(data[i ..< end]))
        }
        benchmark.stopMeasurement()
        blackHole(chunks.count)
    }

    Benchmark("data.reconstruct") { benchmark in
        // Create chunks
        let originalData = Data(repeating: 0x42, count: 1_048_576) // 1MB
        let chunkSize = 1024
        var chunks: [Data] = []
        chunks.reserveCapacity(originalData.count / chunkSize + 1)
        for i in stride(from: 0, to: originalData.count, by: chunkSize) {
            let end = min(i + chunkSize, originalData.count)
            chunks.append(Data(originalData[i ..< end]))
        }

        benchmark.startMeasurement()
        // Benchmark data concatenation (baseline for availability reconstruction)
        var reconstructed = Data()
        reconstructed.reserveCapacity(originalData.count)
        for chunk in chunks {
            reconstructed.append(chunk)
        }
        benchmark.stopMeasurement()
        blackHole(reconstructed.count)
    }

    // MARK: - Hash operations (baseline for proof operations)

    Benchmark("hash.stateroot") { benchmark in
        let (_, genesisState) = try await createGenesis(config: config)

        benchmark.startMeasurement()
        // Benchmark state root computation and hashing (baseline for proof generation)
        let stateRoot = await genesisState.value.stateRoot
        let proofHash = stateRoot.blake2b256hash()
        benchmark.stopMeasurement()
        blackHole(proofHash)
    }

    Benchmark("hash.compare") { benchmark in
        let (_, genesisState) = try await createGenesis(config: config)
        let stateRoot = await genesisState.value.stateRoot
        let proofHash = stateRoot.blake2b256hash()

        benchmark.startMeasurement()
        // Benchmark hash comparison (baseline for proof verification)
        let isValid = proofHash == stateRoot.blake2b256hash()
        benchmark.stopMeasurement()
        blackHole(isValid)
    }

    // MARK: - Erasure coding operations

    Benchmark("erasure.encode.logic") { benchmark in
        // Create data to encode using actual config values
        let data = Data(repeating: 0x42, count: 1024)
        let basicSize = config.value.erasureCodedPieceSize
        let recoveryCount = config.value.totalNumberOfValidators

        benchmark.startMeasurement()
        // Use actual erasure encoding from Utils
        let shards = try ErasureCoding.chunk(data: data, basicSize: basicSize, recoveryCount: recoveryCount)
        benchmark.stopMeasurement()
        blackHole(shards.count)
    }

    Benchmark("erasure.decode.logic") { benchmark in
        _ = try await createGenesis(config: config)

        // Create encoded shards for reconstruction using actual config values
        let originalData = Data(repeating: 0x42, count: 1024)
        let basicSize = config.value.erasureCodedPieceSize
        let recoveryCount = config.value.totalNumberOfValidators
        let originalCount = basicSize / 2

        let shardsData = try ErasureCoding.chunk(data: originalData, basicSize: basicSize, recoveryCount: recoveryCount)
        let typed = shardsData.enumerated().map { ErasureCoding.Shard(data: $0.element, index: UInt32($0.offset)) }

        benchmark.startMeasurement()
        // Use actual erasure reconstruction from Utils
        let reconstructed = try ErasureCoding.reconstruct(
            shards: Array(typed.prefix(originalCount)),
            basicSize: basicSize,
            originalCount: originalCount,
            recoveryCount: recoveryCount,
            originalLength: originalData.count,
        )
        benchmark.stopMeasurement()
        blackHole(reconstructed.count)
    }

    // MARK: - Validator committee operations

    Benchmark("validator.committee") { benchmark in
        let (_, genesisState) = try await createGenesis(config: config)
        let validators = genesisState.value.currentValidators

        benchmark.startMeasurement()
        // Benchmark committee selection (Array.prefix operation)
        let committeeSize = min(100, validators.array.count)
        let committee = Array(validators.array.prefix(committeeSize))
        benchmark.stopMeasurement()
        blackHole(committee.count)
    }

    Benchmark("validator.ticket.selection") { benchmark in
        let (_, genesisState) = try await createGenesis(config: config)

        benchmark.startMeasurement()
        // Benchmark ticket selection (Array.first access)
        let tickets = genesisState.value.safroleState.ticketsAccumulator.array
        let selectedTicket = tickets.first
        benchmark.stopMeasurement()
        blackHole(selectedTicket)
    }

    Benchmark("validator.epoch.change") { benchmark in
        let (_, genesisState) = try await createGenesis(config: config)

        benchmark.startMeasurement()
        // Benchmark epoch calculation (arithmetic and timeslotToEpochIndex)
        // Use multiple iterations to ensure measurable time
        for _ in 0 ..< 10000 {
            let epochLength = config.value.epochLength
            let currentTimeslot = genesisState.value.timeslot
            let currentEpoch = currentTimeslot.timeslotToEpochIndex(config: config)
            let nextEpoch = currentEpoch + 1
            blackHole(epochLength)
            blackHole(currentEpoch)
            blackHole(nextEpoch)
        }
        benchmark.stopMeasurement()
    }
}
