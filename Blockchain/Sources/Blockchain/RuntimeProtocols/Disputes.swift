import Utils

public enum DisputesError: Error {
    case invalidEpoch
    case invalidValidatorIndex
    case invalidJudgementSignature
    case invalidCulpritSigner
    case invalidFaultSigner
    case duplicatedReport
    case invalidJudgementsCount
    case expectInFaults
    case expectInCulprits
    case invalidPublicKey
    case invalidFaults
    case invalidCulprit
}

public struct ReportItem: Sendable, Equatable, Codable {
    public var workReport: WorkReport
    public var timeslot: TimeslotIndex

    public init(
        workReport: WorkReport,
        timeslot: TimeslotIndex
    ) {
        self.workReport = workReport
        self.timeslot = timeslot
    }
}

extension ReportItem: Validate {
    public typealias Config = ProtocolConfigRef
}

public struct DisputesPostState: Sendable, Equatable {
    public var judgements: JudgementsState
    public var reports: ConfigFixedSizeArray<
        ReportItem?,
        ProtocolConfig.TotalNumberOfCores
    >

    public init(
        judgements: JudgementsState,
        reports: ConfigFixedSizeArray<
            ReportItem?,
            ProtocolConfig.TotalNumberOfCores
        >
    ) {
        self.judgements = judgements
        self.reports = reports
    }
}

public protocol Disputes {
    var judgements: JudgementsState { get }
    var reports: ConfigFixedSizeArray<
        ReportItem?,
        ProtocolConfig.TotalNumberOfCores
    > { get }
    var timeslot: TimeslotIndex { get }
    var currentValidators: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    > { get }
    var previousValidators: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    > { get }

    func update(config: ProtocolConfigRef, disputes: ExtrinsicDisputes) throws(DisputesError) -> (
        state: DisputesPostState,
        offenders: [Ed25519PublicKey]
    )

    mutating func mergeWith(postState: DisputesPostState)
}

extension Disputes {
    public func update(config: ProtocolConfigRef, disputes: ExtrinsicDisputes) throws(DisputesError) -> (
        state: DisputesPostState,
        offenders: [Ed25519PublicKey]
    ) {
        var newJudgements = judgements
        var newReports = reports
        var offenders: [Ed25519PublicKey] = []

        let epochLength = UInt32(config.value.epochLength)
        let currentEpoch = timeslot / epochLength
        let lastEpoch = currentEpoch == 0 ? nil : currentEpoch - 1

        for verdict in disputes.verdicts {
            let isCurrent = verdict.epoch == currentEpoch
            let isLast = verdict.epoch == lastEpoch
            guard isCurrent || isLast else {
                throw .invalidEpoch
            }

            let validators = isCurrent ? currentValidators : previousValidators

            for judgement in verdict.judgements {
                guard let signer = validators[safe: Int(judgement.validatorIndex)]?.ed25519 else {
                    throw .invalidValidatorIndex
                }

                let prefix = judgement.isValid ? SigningContext.valid : SigningContext.invalid
                let payload = prefix + verdict.reportHash.data
                let pubkey = try Result { try Ed25519.PublicKey(from: signer) }
                    .mapError { _ in DisputesError.invalidPublicKey }
                    .get()
                guard pubkey.verify(signature: judgement.signature, message: payload) else {
                    throw .invalidJudgementSignature
                }
            }
        }

        var validSigners = Set<Ed25519PublicKey>(currentValidators.map(\.ed25519))
        validSigners.formUnion(previousValidators.map(\.ed25519))
        validSigners.subtract(judgements.punishSet)

        for culprit in disputes.culprits {
            guard validSigners.contains(culprit.validatorKey) else {
                throw .invalidCulpritSigner
            }

            newJudgements.punishSet.insert(culprit.validatorKey)
            offenders.append(culprit.validatorKey)
        }

        for fault in disputes.faults {
            guard validSigners.contains(fault.validatorKey) else {
                throw .invalidFaultSigner
            }

            newJudgements.punishSet.insert(fault.validatorKey)
            offenders.append(fault.validatorKey)
        }

        var allReports = Set(disputes.verdicts.map(\.reportHash))
        allReports.formUnion(judgements.goodSet)
        allReports.formUnion(judgements.banSet)
        allReports.formUnion(judgements.wonkySet)

        let expectedReportCount = disputes.verdicts.count + judgements.goodSet.count + judgements.banSet.count + judgements.wonkySet.count

        guard allReports.count == expectedReportCount else {
            throw .duplicatedReport
        }

        let votes = disputes.verdicts.map {
            (hash: $0.reportHash, vote: $0.judgements.reduce(into: 0) { $0 += $1.isValid ? 1 : 0 })
        }

        var tobeRemoved = Set<Data32>()
        let third_validators = config.value.totalNumberOfValidators / 3
        let two_third_plus_one_validators = config.value.totalNumberOfValidators * 2 / 3 + 1
        for (hash, vote) in votes {
            if vote == 0 {
                // Any verdict containing solely invalid judgements
                // implies the same report having at least two valid entries in the culprits sequence c
                let culprits = disputes.culprits.filter { $0.reportHash == hash }
                guard culprits.count >= 2 else {
                    throw .expectInCulprits
                }

                tobeRemoved.insert(hash)
                newJudgements.banSet.insert(hash)

                let faults = disputes.faults.filter { $0.reportHash == hash }
                for fault in faults {
                    // check faults are indeed invalid
                    guard fault.vote else {
                        throw .invalidFaults
                    }
                }
            } else if vote == third_validators {
                // wonky
                tobeRemoved.insert(hash)
                newJudgements.wonkySet.insert(hash)
            } else if vote == two_third_plus_one_validators {
                // any verdict containing solely valid judgements
                // implies the same report having at least one valid entry in the faults sequence f
                let faults = disputes.faults.filter { $0.reportHash == hash }
                guard faults.count >= 1 else {
                    throw .expectInFaults
                }
                for fault in faults {
                    // check faults are indeed invalid
                    guard !fault.vote else {
                        throw .invalidFaults
                    }
                }

                newJudgements.goodSet.insert(hash)
            } else {
                throw .invalidJudgementsCount
            }
        }

        for culprit in disputes.culprits {
            guard newJudgements.banSet.contains(culprit.reportHash) else {
                throw .invalidCulprit
            }
        }

        for i in 0 ..< newReports.count {
            if let report = newReports[i]?.workReport {
                let hash = report.hash()
                if tobeRemoved.contains(hash) {
                    newReports[i] = nil
                }
            }
        }

        return (
            state: DisputesPostState(
                judgements: newJudgements,
                reports: newReports
            ),
            offenders: offenders
        )
    }
}
