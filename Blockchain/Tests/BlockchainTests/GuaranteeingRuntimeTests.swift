@testable import Blockchain
import Foundation
import Testing
import Utils

struct GuaranteeingRuntimeTests {
    private let config = ProtocolConfigRef.tiny

    @Test
    func requiredStorageKeysIncludesEachDigestServiceAccount() throws {
        let state = try GuaranteeingState(config: config)
        let extrinsic = try makeExtrinsic(digests: [
            makeDigest(serviceIndex: 7, codeHash: data32(1), gasLimit: Gas(10)),
            makeDigest(serviceIndex: 8, codeHash: data32(2), gasLimit: Gas(20)),
        ])

        let encodedKeys = state.requiredStorageKeys(extrinsic: extrinsic).map { $0.encode() }

        #expect(encodedKeys == [
            StateKeys.ServiceAccountKey(index: 7).encode(),
            StateKeys.ServiceAccountKey(index: 8).encode(),
        ])
    }

    @Test
    func requiredStorageKeysDeduplicatesRepeatedServiceAccounts() throws {
        let state = try GuaranteeingState(config: config)
        let extrinsic = try makeExtrinsic(digests: [
            makeDigest(serviceIndex: 7, codeHash: data32(1), gasLimit: Gas(10)),
            makeDigest(serviceIndex: 7, codeHash: data32(1), gasLimit: Gas(20)),
            makeDigest(serviceIndex: 8, codeHash: data32(2), gasLimit: Gas(30)),
        ])

        let encodedKeys = state.requiredStorageKeys(extrinsic: extrinsic).map { $0.encode() }

        #expect(encodedKeys == [
            StateKeys.ServiceAccountKey(index: 7).encode(),
            StateKeys.ServiceAccountKey(index: 8).encode(),
        ])
    }

    @Test
    func validateGuaranteesAcceptsMatchingServiceCodeAndGas() async throws {
        let account = makeAccount(codeHash: data32(1), minAccumlateGas: Gas(10))
        let state = try GuaranteeingState(config: config, serviceAccounts: [7: account])
        let extrinsic = try makeExtrinsic(digests: [
            makeDigest(serviceIndex: 7, codeHash: data32(1), gasLimit: Gas(10)),
        ])

        try await state.validateGuarantees(config: config, extrinsic: extrinsic)
    }

    @Test
    func validateGuaranteesRejectsMissingServiceAccount() async {
        let state = try! GuaranteeingState(config: config)
        let extrinsic = try! makeExtrinsic(digests: [
            makeDigest(serviceIndex: 7, codeHash: data32(1), gasLimit: Gas(10)),
        ])

        await expectGuaranteeingError(.invalidServiceIndex) {
            try await state.validateGuarantees(config: config, extrinsic: extrinsic)
        }
    }

    @Test
    func validateGuaranteesRejectsMismatchedCodeHash() async {
        let account = makeAccount(codeHash: data32(1), minAccumlateGas: Gas(10))
        let state = try! GuaranteeingState(config: config, serviceAccounts: [7: account])
        let extrinsic = try! makeExtrinsic(digests: [
            makeDigest(serviceIndex: 7, codeHash: data32(2), gasLimit: Gas(10)),
        ])

        await expectGuaranteeingError(.invalidResultCodeHash) {
            try await state.validateGuarantees(config: config, extrinsic: extrinsic)
        }
    }

    @Test
    func validateGuaranteesRejectsDigestBelowServiceMinimumGas() async {
        let account = makeAccount(codeHash: data32(1), minAccumlateGas: Gas(11))
        let state = try! GuaranteeingState(config: config, serviceAccounts: [7: account])
        let extrinsic = try! makeExtrinsic(digests: [
            makeDigest(serviceIndex: 7, codeHash: data32(1), gasLimit: Gas(10)),
        ])

        await expectGuaranteeingError(.invalidServiceGas) {
            try await state.validateGuarantees(config: config, extrinsic: extrinsic)
        }
    }

    @Test
    func validateGuaranteesRejectsTotalGasOverBlockLimit() async {
        let account = makeAccount(codeHash: data32(1), minAccumlateGas: Gas(0))
        let state = try! GuaranteeingState(config: config, serviceAccounts: [7: account])
        let extrinsic = try! makeExtrinsic(digests: [
            makeDigest(
                serviceIndex: 7,
                codeHash: data32(1),
                gasLimit: config.value.workReportAccumulationGas + Gas(1),
            ),
        ])

        await expectGuaranteeingError(.outOfGas) {
            try await state.validateGuarantees(config: config, extrinsic: extrinsic)
        }
    }

    private func makeAccount(codeHash: Data32, minAccumlateGas: Gas) -> ServiceAccountDetails {
        var account = ServiceAccount.dummy(config: config).toDetails()
        account.codeHash = codeHash
        account.minAccumlateGas = minAccumlateGas
        return account
    }

    private func makeDigest(serviceIndex: ServiceIndex, codeHash: Data32, gasLimit: Gas) -> WorkDigest {
        WorkDigest(
            serviceIndex: serviceIndex,
            codeHash: codeHash,
            payloadHash: data32(3),
            gasLimit: gasLimit,
            result: WorkResult(.success(Data())),
            gasUsed: 0,
            importsCount: 0,
            exportsCount: 0,
            extrinsicsCount: 0,
            extrinsicsSize: 0,
        )
    }

    private func makeExtrinsic(digests: [WorkDigest]) throws -> ExtrinsicGuarantees {
        var report = WorkReport.dummy(config: config)
        report.digests = try ConfigLimitedSizeArray(config: config, array: digests)
        let guarantee = ExtrinsicGuarantees.GuaranteeItem(
            workReport: report,
            timeslot: 0,
            credential: [
                .init(index: 0, signature: data64(1)),
                .init(index: 1, signature: data64(2)),
            ],
        )
        return try ExtrinsicGuarantees(guarantees: ConfigLimitedSizeArray(config: config, array: [guarantee]))
    }

    private func expectGuaranteeingError(
        _ expected: GuaranteeingError,
        operation: () async throws -> Void,
    ) async {
        do {
            try await operation()
            Issue.record("Expected \(expected)")
        } catch let error as GuaranteeingError {
            #expect(sameGuaranteeingError(error, expected))
        } catch {
            Issue.record("Expected \(expected), got \(error)")
        }
    }
}

private struct GuaranteeingState: Guaranteeing {
    var entropyPool: EntropyPool
    var currentValidators: ConfigFixedSizeArray<ValidatorKey, ProtocolConfig.TotalNumberOfValidators>
    var previousValidators: ConfigFixedSizeArray<ValidatorKey, ProtocolConfig.TotalNumberOfValidators>
    var reports: ConfigFixedSizeArray<ReportItem?, ProtocolConfig.TotalNumberOfCores>
    var coreAuthorizationPool: ConfigFixedSizeArray<
        ConfigLimitedSizeArray<Data32, ProtocolConfig.Int0, ProtocolConfig.MaxAuthorizationsPoolItems>,
        ProtocolConfig.TotalNumberOfCores
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
        accumulationHistory = try ConfigFixedSizeArray(config: config, defaultValue: SortedUniqueArray<Data32>(sortedUnchecked: []))
        self.serviceAccounts = serviceAccounts
    }

    func serviceAccount(index: ServiceIndex) async throws -> ServiceAccountDetails? {
        serviceAccounts[index]
    }
}

private func sameGuaranteeingError(_ lhs: GuaranteeingError, _ rhs: GuaranteeingError) -> Bool {
    switch (lhs, rhs) {
    case (.invalidGuaranteeSignature, .invalidGuaranteeSignature),
         (.invalidGuaranteeCore, .invalidGuaranteeCore),
         (.coreNotAvailable, .coreNotAvailable),
         (.invalidReportAuthorizer, .invalidReportAuthorizer),
         (.invalidServiceIndex, .invalidServiceIndex),
         (.missingWorkResults, .missingWorkResults),
         (.outOfGas, .outOfGas),
         (.invalidContext, .invalidContext),
         (.duplicatedWorkPackage, .duplicatedWorkPackage),
         (.prerequisiteNotFound, .prerequisiteNotFound),
         (.invalidResultCodeHash, .invalidResultCodeHash),
         (.invalidServiceGas, .invalidServiceGas),
         (.invalidPublicKey, .invalidPublicKey),
         (.invalidSegmentLookup, .invalidSegmentLookup),
         (.futureReportSlot, .futureReportSlot):
        true
    default:
        false
    }
}
