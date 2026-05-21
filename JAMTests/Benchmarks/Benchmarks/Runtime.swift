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

    // MARK: - Guaranteeing runtime protocol operations

    Benchmark("runtime.guaranteeing.requiredStorageKeys.duplicates", configuration: BokaBenchmark.configuration()) { benchmark in
        let state = try RuntimeGuaranteeingBenchmarkState(config: config)
        let extrinsic = try runtimeGuaranteingExtrinsic(
            config: config,
            serviceIndices: Array(repeating: 7, count: config.value.maxWorkItems),
            codeHash: runtimeData32(1),
            gasLimit: Gas(10),
        )

        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            let keys = state.requiredStorageKeys(extrinsic: extrinsic)
            blackHole(keys)
        }
        benchmark.stopMeasurement()
    }

    Benchmark("runtime.guaranteeing.validate.repeatedService", configuration: BokaBenchmark.configuration()) { benchmark in
        let account = runtimeServiceAccount(codeHash: runtimeData32(1), minAccumlateGas: Gas(10), config: config)
        let state = try RuntimeGuaranteeingBenchmarkState(config: config, serviceAccounts: [7: account])
        let extrinsic = try runtimeGuaranteingExtrinsic(
            config: config,
            serviceIndices: Array(repeating: 7, count: config.value.maxWorkItems),
            codeHash: runtimeData32(1),
            gasLimit: Gas(10),
        )

        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            try await state.validateGuarantees(config: config, extrinsic: extrinsic)
        }
        benchmark.stopMeasurement()
    }
}

private struct RuntimeGuaranteeingBenchmarkState: Guaranteeing {
    var entropyPool: EntropyPool
    var currentValidators: ConfigFixedSizeArray<ValidatorKey, ProtocolConfig.TotalNumberOfValidators>
    var previousValidators: ConfigFixedSizeArray<ValidatorKey, ProtocolConfig.TotalNumberOfValidators>
    var reports: ConfigFixedSizeArray<ReportItem?, ProtocolConfig.TotalNumberOfCores>
    var coreAuthorizationPool: ConfigFixedSizeArray<
        ConfigLimitedSizeArray<Data32, ProtocolConfig.Int0, ProtocolConfig.MaxAuthorizationsPoolItems>,
        ProtocolConfig.TotalNumberOfCores,
    >
    var recentHistory: RecentHistory
    var offenders: Set<Ed25519PublicKey>
    var accumulationQueue: ConfigFixedSizeArray<[AccumulationQueueItem], ProtocolConfig.EpochLength>
    var accumulationHistory: ConfigFixedSizeArray<SortedUniqueArray<Data32>, ProtocolConfig.EpochLength>
    var serviceAccounts: [ServiceIndex: ServiceAccountDetails]

    init(
        config: ProtocolConfigRef,
        serviceAccounts: [ServiceIndex: ServiceAccountDetails] = [:],
    ) throws {
        entropyPool = EntropyPool((Data32(), Data32(), Data32(), Data32()))
        currentValidators = try ConfigFixedSizeArray(config: config, defaultValue: ValidatorKey())
        previousValidators = try ConfigFixedSizeArray(config: config, defaultValue: ValidatorKey())
        reports = try ConfigFixedSizeArray(
            config: config,
            array: Array(repeating: nil, count: config.value.totalNumberOfCores),
        )
        coreAuthorizationPool = try ConfigFixedSizeArray(
            config: config,
            defaultValue: ConfigLimitedSizeArray(config: config),
        )
        recentHistory = RecentHistory.dummy(config: config)
        offenders = []
        accumulationQueue = try ConfigFixedSizeArray(config: config, defaultValue: [])
        accumulationHistory = try ConfigFixedSizeArray(
            config: config,
            defaultValue: SortedUniqueArray<Data32>(sortedUnchecked: []),
        )
        self.serviceAccounts = serviceAccounts
    }

    func serviceAccount(index: ServiceIndex) async throws -> ServiceAccountDetails? {
        serviceAccounts[index]
    }
}

private func runtimeGuaranteingExtrinsic(
    config: ProtocolConfigRef,
    serviceIndices: [ServiceIndex],
    codeHash: Data32,
    gasLimit: Gas,
) throws -> ExtrinsicGuarantees {
    let digests = serviceIndices.map {
        WorkDigest(
            serviceIndex: $0,
            codeHash: codeHash,
            payloadHash: runtimeData32(2),
            gasLimit: gasLimit,
            result: WorkResult(.success(Data())),
            gasUsed: 0,
            importsCount: 0,
            exportsCount: 0,
            extrinsicsCount: 0,
            extrinsicsSize: 0,
        )
    }

    var report = WorkReport.dummy(config: config)
    report.digests = try ConfigLimitedSizeArray(config: config, array: digests)

    let guarantee = ExtrinsicGuarantees.GuaranteeItem(
        workReport: report,
        timeslot: 0,
        credential: [
            .init(index: 0, signature: runtimeData64(1)),
            .init(index: 1, signature: runtimeData64(2)),
        ],
    )
    return try ExtrinsicGuarantees(guarantees: ConfigLimitedSizeArray(config: config, array: [guarantee]))
}

private func runtimeServiceAccount(
    codeHash: Data32,
    minAccumlateGas: Gas,
    config: ProtocolConfigRef,
) -> ServiceAccountDetails {
    var account = ServiceAccount.dummy(config: config).toDetails()
    account.codeHash = codeHash
    account.minAccumlateGas = minAccumlateGas
    return account
}

private func runtimeData32(_ byte: UInt8) -> Data32 {
    Data32(Data(repeating: byte, count: 32))!
}

private func runtimeData64(_ byte: UInt8) -> Data64 {
    Data64(Data(repeating: byte, count: 64))!
}
