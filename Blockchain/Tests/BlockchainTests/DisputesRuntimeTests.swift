@testable import Blockchain
import Foundation
import Testing
import Utils

struct DisputesRuntimeTests {
    private let config = ProtocolConfigRef.tiny

    @Test
    func updateBansInvalidReportAndRemovesStoredReport() throws {
        let keys = try makeValidatorKeys()
        let report = disputeReport(config: config, packageHash: data32(41))
        let reportHash = report.hash()
        let state = try DisputesState(config: config, keys: keys, report: report)
        let disputes = try ExtrinsicDisputes(
            verdicts: [
                makeVerdict(reportHash: reportHash, epoch: 1, validVotes: 0, keys: keys),
            ],
            culprits: sortedCulprits([
                makeCulprit(reportHash: reportHash, key: keys[0]),
                makeCulprit(reportHash: reportHash, key: keys[1]),
            ]),
            faults: [],
        )

        let result = try state.update(config: config, disputes: disputes)

        #expect(result.state.judgements.banSet == [reportHash])
        #expect(result.state.judgements.goodSet.isEmpty)
        #expect(result.state.judgements.wonkySet.isEmpty)
        #expect(result.state.reports[0] == nil)
        #expect(Set(result.offenders) == [keys[0].publicKey, keys[1].publicKey])
    }

    @Test
    func updateMarksValidReportGoodWhenFaultIsProvided() throws {
        let keys = try makeValidatorKeys()
        let report = disputeReport(config: config, packageHash: data32(42))
        let reportHash = report.hash()
        let state = try DisputesState(config: config, keys: keys, report: report)
        let disputes = try ExtrinsicDisputes(
            verdicts: [
                makeVerdict(reportHash: reportHash, epoch: 1, validVotes: 5, keys: keys),
            ],
            culprits: [],
            faults: sortedFaults([
                makeFault(reportHash: reportHash, vote: false, key: keys[5]),
            ]),
        )

        let result = try state.update(config: config, disputes: disputes)

        #expect(result.state.judgements.goodSet == [reportHash])
        #expect(result.state.judgements.banSet.isEmpty)
        #expect(result.state.reports[0]?.workReport == report)
        #expect(result.offenders == [keys[5].publicKey])
    }

    @Test
    func updateMarksWonkyReportAndRemovesStoredReport() throws {
        let keys = try makeValidatorKeys()
        let report = disputeReport(config: config, packageHash: data32(43))
        let reportHash = report.hash()
        let state = try DisputesState(config: config, keys: keys, report: report)
        let disputes = try ExtrinsicDisputes(
            verdicts: [
                makeVerdict(reportHash: reportHash, epoch: 1, validVotes: 2, keys: keys),
            ],
            culprits: [],
            faults: [],
        )

        let result = try state.update(config: config, disputes: disputes)

        #expect(result.state.judgements.wonkySet == [reportHash])
        #expect(result.state.judgements.banSet.isEmpty)
        #expect(result.state.reports[0] == nil)
        #expect(result.offenders.isEmpty)
    }

    @Test
    func updateRejectsVerdictOutsideCurrentAndPreviousEpoch() throws {
        let keys = try makeValidatorKeys()
        let state = try DisputesState(config: config, keys: keys, timeslot: 24)
        let disputes = try ExtrinsicDisputes(
            verdicts: [
                makeVerdict(reportHash: data32(44), epoch: 0, validVotes: 5, keys: keys),
            ],
            culprits: [],
            faults: [],
        )

        expectDisputesError(.invalidEpoch) {
            _ = try state.update(config: config, disputes: disputes)
        }
    }

    @Test
    func updateRejectsDuplicateReportAlreadyJudged() throws {
        let keys = try makeValidatorKeys()
        let reportHash = data32(45)
        let state = try DisputesState(
            config: config,
            keys: keys,
            judgements: JudgementsState(goodSet: [reportHash], banSet: [], wonkySet: [], punishSet: []),
        )
        let disputes = try ExtrinsicDisputes(
            verdicts: [
                makeVerdict(reportHash: reportHash, epoch: 1, validVotes: 5, keys: keys),
            ],
            culprits: [],
            faults: [],
        )

        expectDisputesError(.duplicatedReport) {
            _ = try state.update(config: config, disputes: disputes)
        }
    }

    @Test
    func updateRejectsValidVerdictWithoutFault() throws {
        let keys = try makeValidatorKeys()
        let state = try DisputesState(config: config, keys: keys)
        let disputes = try ExtrinsicDisputes(
            verdicts: [
                makeVerdict(reportHash: data32(46), epoch: 1, validVotes: 5, keys: keys),
            ],
            culprits: [],
            faults: [],
        )

        expectDisputesError(.expectInFaults) {
            _ = try state.update(config: config, disputes: disputes)
        }
    }

    @Test
    func updateRejectsInvalidVerdictWithoutCulprits() throws {
        let keys = try makeValidatorKeys()
        let state = try DisputesState(config: config, keys: keys)
        let disputes = try ExtrinsicDisputes(
            verdicts: [
                makeVerdict(reportHash: data32(47), epoch: 1, validVotes: 0, keys: keys),
            ],
            culprits: [],
            faults: [],
        )

        expectDisputesError(.expectInCulprits) {
            _ = try state.update(config: config, disputes: disputes)
        }
    }

    @Test
    func validateAcceptsSortedSignedDisputes() throws {
        let keys = try makeValidatorKeys()
        let reportHash = data32(48)
        let disputes = try ExtrinsicDisputes(
            verdicts: [
                makeVerdict(reportHash: reportHash, epoch: 1, validVotes: 5, keys: keys),
            ],
            culprits: sortedCulprits([
                makeCulprit(reportHash: reportHash, key: keys[0]),
            ]),
            faults: sortedFaults([
                makeFault(reportHash: reportHash, vote: false, key: keys[1]),
            ]),
        )

        try disputes.validate(config: config)
    }

    @Test
    func validateRejectsUnsortedJudgements() throws {
        let keys = try makeValidatorKeys()
        let first = try makeJudgement(reportHash: data32(49), isValid: true, validatorIndex: 1, key: keys[1])
        let second = try makeJudgement(reportHash: data32(49), isValid: true, validatorIndex: 0, key: keys[0])
        let verdict = try ExtrinsicDisputes.VerdictItem(
            reportHash: data32(49),
            epoch: 1,
            judgements: ConfigFixedSizeArray(config: config, array: [first, second, first, second, first]),
        )
        let disputes = ExtrinsicDisputes(verdicts: [verdict], culprits: [], faults: [])

        expectExtrinsicDisputesError(.judgementsNotSorted) {
            try disputes.validate(config: config)
        }
    }

    @Test
    func validateRejectsInvalidFaultSignature() throws {
        let keys = try makeValidatorKeys()
        let reportHash = data32(50)
        let disputes = ExtrinsicDisputes(
            verdicts: [],
            culprits: [],
            faults: sortedFaults([
                ExtrinsicDisputes.FaultItem(
                    reportHash: reportHash,
                    vote: false,
                    validatorKey: keys[0].publicKey,
                    signature: data64(1),
                ),
            ]),
        )

        expectExtrinsicDisputesError(.invalidFaultSignature) {
            try disputes.validate(config: config)
        }
    }
}

private struct DisputeValidatorKey {
    let secret: Ed25519.SecretKey
    let publicKey: Ed25519PublicKey

    var validatorKey: ValidatorKey {
        ValidatorKey(
            bandersnatch: BandersnatchPublicKey(),
            ed25519: publicKey,
            bls: BLSKey(),
            metadata: Data128(),
        )
    }
}

private struct DisputesState: Disputes {
    var judgements: JudgementsState
    var reports: ConfigFixedSizeArray<ReportItem?, ProtocolConfig.TotalNumberOfCores>
    var timeslot: TimeslotIndex
    var currentValidators: ConfigFixedSizeArray<ValidatorKey, ProtocolConfig.TotalNumberOfValidators>
    var previousValidators: ConfigFixedSizeArray<ValidatorKey, ProtocolConfig.TotalNumberOfValidators>

    init(
        config: ProtocolConfigRef,
        keys: [DisputeValidatorKey],
        timeslot: TimeslotIndex = 12,
        report: WorkReport? = nil,
        judgements: JudgementsState = JudgementsState.dummy(config: ProtocolConfigRef.tiny),
    ) throws {
        self.judgements = judgements
        self.timeslot = timeslot
        currentValidators = try ConfigFixedSizeArray(config: config, array: keys.map(\.validatorKey))
        previousValidators = currentValidators

        var reportSlots = [ReportItem?](repeating: nil, count: config.value.totalNumberOfCores)
        if let report {
            reportSlots[0] = ReportItem(workReport: report, timeslot: timeslot)
        }
        reports = try ConfigFixedSizeArray(config: config, array: reportSlots)
    }

    mutating func mergeWith(postState: DisputesPostState) {
        judgements = postState.judgements
        reports = postState.reports
    }
}

private func makeValidatorKeys(count: Int = ProtocolConfigRef.tiny.value.totalNumberOfValidators) throws -> [DisputeValidatorKey] {
    try (0 ..< count).map { index in
        let seed = data32(UInt8(index + 1))
        let secret = try Ed25519.SecretKey(from: seed)
        return DisputeValidatorKey(secret: secret, publicKey: secret.publicKey.data)
    }
}

private func disputeReport(config: ProtocolConfigRef, packageHash: Data32) -> WorkReport {
    var report = WorkReport.dummy(config: config)
    report.packageSpecification.workPackageHash = packageHash
    return report
}

private func makeVerdict(
    reportHash: Data32,
    epoch: EpochIndex,
    validVotes: Int,
    keys: [DisputeValidatorKey],
) throws -> ExtrinsicDisputes.VerdictItem {
    let judgements = try (0 ..< ProtocolConfig.TwoThirdValidatorsPlusOne.read(config: ProtocolConfigRef.tiny)).map { index in
        try makeJudgement(
            reportHash: reportHash,
            isValid: index < validVotes,
            validatorIndex: ValidatorIndex(index),
            key: keys[index],
        )
    }

    return try ExtrinsicDisputes.VerdictItem(
        reportHash: reportHash,
        epoch: epoch,
        judgements: ConfigFixedSizeArray(config: ProtocolConfigRef.tiny, array: judgements),
    )
}

private func makeJudgement(
    reportHash: Data32,
    isValid: Bool,
    validatorIndex: ValidatorIndex,
    key: DisputeValidatorKey,
) throws -> ExtrinsicDisputes.VerdictItem.SignatureItem {
    let payload = (isValid ? SigningContext.valid : SigningContext.invalid) + reportHash.data
    return try ExtrinsicDisputes.VerdictItem.SignatureItem(
        isValid: isValid,
        validatorIndex: validatorIndex,
        signature: key.secret.sign(message: payload),
    )
}

private func makeCulprit(
    reportHash: Data32,
    key: DisputeValidatorKey,
) throws -> ExtrinsicDisputes.CulpritItem {
    try ExtrinsicDisputes.CulpritItem(
        reportHash: reportHash,
        validatorKey: key.publicKey,
        signature: key.secret.sign(message: SigningContext.guarantee + reportHash.data),
    )
}

private func makeFault(
    reportHash: Data32,
    vote: Bool,
    key: DisputeValidatorKey,
) throws -> ExtrinsicDisputes.FaultItem {
    let payload = (vote ? SigningContext.valid : SigningContext.invalid) + reportHash.data
    return try ExtrinsicDisputes.FaultItem(
        reportHash: reportHash,
        vote: vote,
        validatorKey: key.publicKey,
        signature: key.secret.sign(message: payload),
    )
}

private func sortedCulprits(_ culprits: [ExtrinsicDisputes.CulpritItem]) -> [ExtrinsicDisputes.CulpritItem] {
    culprits.sorted { $0.validatorKey < $1.validatorKey }
}

private func sortedFaults(_ faults: [ExtrinsicDisputes.FaultItem]) -> [ExtrinsicDisputes.FaultItem] {
    faults.sorted { $0.validatorKey < $1.validatorKey }
}

private func expectDisputesError(
    _ expected: DisputesError,
    operation: () throws -> Void,
) {
    do {
        try operation()
        Issue.record("Expected \(expected)")
    } catch let error as DisputesError {
        #expect(sameDisputesError(error, expected))
    } catch {
        Issue.record("Expected \(expected), got \(error)")
    }
}

private func sameDisputesError(_ lhs: DisputesError, _ rhs: DisputesError) -> Bool {
    switch (lhs, rhs) {
    case (.invalidEpoch, .invalidEpoch),
         (.invalidValidatorIndex, .invalidValidatorIndex),
         (.invalidJudgementSignature, .invalidJudgementSignature),
         (.invalidCulpritSigner, .invalidCulpritSigner),
         (.invalidFaultSigner, .invalidFaultSigner),
         (.duplicatedReport, .duplicatedReport),
         (.invalidJudgementsCount, .invalidJudgementsCount),
         (.expectInFaults, .expectInFaults),
         (.expectInCulprits, .expectInCulprits),
         (.invalidPublicKey, .invalidPublicKey),
         (.invalidFaults, .invalidFaults),
         (.invalidCulprit, .invalidCulprit):
        true
    default:
        false
    }
}

private func expectExtrinsicDisputesError(
    _ expected: ExtrinsicDisputes.Error,
    operation: () throws -> Void,
) {
    do {
        try operation()
        Issue.record("Expected \(expected)")
    } catch let error as ExtrinsicDisputes.Error {
        #expect(sameExtrinsicDisputesError(error, expected))
    } catch {
        Issue.record("Expected \(expected), got \(error)")
    }
}

private func sameExtrinsicDisputesError(
    _ lhs: ExtrinsicDisputes.Error,
    _ rhs: ExtrinsicDisputes.Error,
) -> Bool {
    switch (lhs, rhs) {
    case (.verdictsNotSorted, .verdictsNotSorted),
         (.culpritsNotSorted, .culpritsNotSorted),
         (.faultsNotSorted, .faultsNotSorted),
         (.judgementsNotSorted, .judgementsNotSorted),
         (.invalidCulpritSignature, .invalidCulpritSignature),
         (.invalidFaultSignature, .invalidFaultSignature),
         (.invalidPublicKey, .invalidPublicKey):
        true
    default:
        false
    }
}
