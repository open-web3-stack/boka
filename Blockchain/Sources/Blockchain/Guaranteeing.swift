import Codec
import Utils

public enum GuaranteeingError: Error {
    case invalidGuaranteeSignature
    case coreNotAvailable
    case invalidReportAuthorizer
    case invalidServiceIndex
    case outOfGas
    case invalidContext
    case duplicatedWorkPackage
    case prerequistieNotFound
    case invalidResultCodeHash
}

public protocol Guaranteeing {
    var entropyPool: EntropyPool { get }
    var timeslot: TimeslotIndex { get }
    var currentValidators: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    > { get }
    var previousValidators: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    > { get }
    var reports: ConfigFixedSizeArray<
        ReportItem?,
        ProtocolConfig.TotalNumberOfCores
    > { get }
    var coreAuthorizationPool: ConfigFixedSizeArray<
        ConfigLimitedSizeArray<
            Data32,
            ProtocolConfig.Int0,
            ProtocolConfig.MaxAuthorizationsPoolItems
        >,
        ProtocolConfig.TotalNumberOfCores
    > { get }
    var serviceAccounts: [ServiceIndex: ServiceAccount] { get }
    var recentHistory: RecentHistory { get }
    var offenders: Set<Ed25519PublicKey> { get }
}

extension Guaranteeing {
    private func withoutOffenders(keys: [Ed25519PublicKey]) -> [Ed25519PublicKey] {
        keys.map { key in
            if offenders.contains(key) {
                Data32()
            } else {
                key
            }
        }
    }

    private func toCoreAssignment(_ source: [UInt32], n: UInt32, max: UInt32) -> [CoreIndex] {
        source.map { CoreIndex(($0 + n) % max) }
    }

    private func getCoreAssignment(config: ProtocolConfigRef, randomness: Data32, timeslot: TimeslotIndex) -> [CoreIndex] {
        var source = Array(repeating: UInt32(0), count: config.value.totalNumberOfValidators)
        for i in 0 ..< config.value.totalNumberOfValidators {
            source[i] = UInt32(config.value.totalNumberOfCores * i / config.value.totalNumberOfValidators)
        }
        source.shuffle(randomness: randomness)

        let n = timeslot % UInt32(config.value.epochLength) / UInt32(config.value.coreAssignmentRotationPeriod)

        return toCoreAssignment(source, n: n, max: UInt32(config.value.totalNumberOfCores))
    }

    public func update(
        config: ProtocolConfigRef,
        extrinsic: ExtrinsicGuarantees
    ) throws(GuaranteeingError) -> ConfigFixedSizeArray<
        ReportItem?,
        ProtocolConfig.TotalNumberOfCores
    > {
        let coreAssignmentRotationPeriod = UInt32(config.value.coreAssignmentRotationPeriod)

        let currentCoreAssignment = getCoreAssignment(config: config, randomness: entropyPool.t2, timeslot: timeslot)
        let currentCoreKeys = withoutOffenders(keys: currentValidators.map(\.ed25519))

        let isEpochChanging = (timeslot % UInt32(config.value.epochLength)) < coreAssignmentRotationPeriod
        let previousRandomness = isEpochChanging ? entropyPool.t3 : entropyPool.t2
        let previousValidators = isEpochChanging ? previousValidators : currentValidators

        let previousCoreAssignment = getCoreAssignment(
            config: config,
            randomness: previousRandomness,
            timeslot: timeslot - coreAssignmentRotationPeriod
        )
        let pareviousCoreKeys = withoutOffenders(keys: previousValidators.map(\.ed25519))

        var workReportHashes = Set<Data32>()

        var totalMinGasRequirement: Gas = 0

        for guarantee in extrinsic.guarantees {
            let report = guarantee.workReport

            for credential in guarantee.credential {
                let isCurrent = (guarantee.timeslot / coreAssignmentRotationPeriod) == (timeslot / coreAssignmentRotationPeriod)
                let keys = isCurrent ? currentCoreKeys : pareviousCoreKeys
                let key = keys[Int(credential.index)]
                let reportHash = report.hash()
                workReportHashes.insert(reportHash)
                let payload = SigningContext.guarantee + reportHash.data
                guard Ed25519.verify(signature: credential.signature, message: payload, publicKey: key) else {
                    throw .invalidGuaranteeSignature
                }
            }

            let coreIndex = Int(report.coreIndex)

            guard reports[coreIndex] == nil ||
                timeslot >= (guarantee.timeslot + UInt32(config.value.preimageReplacementPeriod))
            else {
                throw .coreNotAvailable
            }

            guard coreAuthorizationPool[coreIndex].contains(report.authorizerHash) else {
                throw .invalidReportAuthorizer
            }

            for result in report.results {
                guard let acc = serviceAccounts[result.serviceIndex] else {
                    throw .invalidServiceIndex
                }

                guard acc.codeHash == result.codeHash else {
                    throw .invalidResultCodeHash
                }

                totalMinGasRequirement += acc.minAccumlateGas
            }
        }

        guard totalMinGasRequirement <= config.value.coreAccumulationGas else {
            throw .outOfGas
        }

        let allRecentWorkReportHashes = Set(recentHistory.items.flatMap(\.workReportHashes.array))
        guard allRecentWorkReportHashes.isDisjoint(with: workReportHashes) else {
            throw .duplicatedWorkPackage
        }

        let contexts = Set(extrinsic.guarantees.map(\.workReport.refinementContext))

        for context in contexts {
            let history = recentHistory.items.first { $0.headerHash == context.anchor.headerHash }
            guard let history else {
                throw .invalidContext
            }
            guard context.anchor.stateRoot == history.stateRoot else {
                throw .invalidContext
            }
            guard context.anchor.beefyRoot == history.mmr.hash() else {
                throw .invalidContext
            }
            guard context.lokupAnchor.timeslot >= timeslot - UInt32(config.value.maxLookupAnchorAge) else {
                throw .invalidContext
            }

            if let prerequistieWorkPackage = context.prerequistieWorkPackage {
                guard allRecentWorkReportHashes.contains(prerequistieWorkPackage) ||
                    workReportHashes.contains(prerequistieWorkPackage)
                else {
                    throw .prerequistieNotFound
                }
            }
        }

        var newReports = reports

        for guarantee in extrinsic.guarantees {
            let report = guarantee.workReport
            let coreIndex = Int(report.coreIndex)
            newReports[coreIndex] = ReportItem(
                workReport: report,
                timeslot: timeslot
            )
        }

        return newReports
    }
}
