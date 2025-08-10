import Codec
import Utils

public enum GuaranteeingError: Error {
    case invalidGuaranteeSignature
    case invalidGuaranteeCore
    case coreNotAvailable
    case invalidReportAuthorizer
    case invalidServiceIndex
    case outOfGas
    case invalidContext
    case duplicatedWorkPackage
    case prerequisiteNotFound
    case invalidResultCodeHash
    case invalidServiceGas
    case invalidPublicKey
    case invalidSegmentLookup
    case futureReportSlot
}

public protocol Guaranteeing {
    var entropyPool: EntropyPool { get }
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
    var recentHistory: RecentHistory { get }
    var offenders: Set<Ed25519PublicKey> { get }
    var accumulationQueue: ConfigFixedSizeArray<
        [AccumulationQueueItem],
        ProtocolConfig.EpochLength
    > { get }
    var accumulationHistory: ConfigFixedSizeArray<
        SortedUniqueArray<Data32>,
        ProtocolConfig.EpochLength
    > { get }

    func serviceAccount(index: ServiceIndex) async throws -> ServiceAccountDetails?
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

    public func getCoreAssignment(config: ProtocolConfigRef, randomness: Data32, timeslot: TimeslotIndex) -> [CoreIndex] {
        var source = Array(repeating: UInt32(0), count: config.value.totalNumberOfValidators)
        for i in 0 ..< config.value.totalNumberOfValidators {
            source[i] = UInt32(config.value.totalNumberOfCores * i / config.value.totalNumberOfValidators)
        }
        source.shuffle(randomness: randomness)

        let n = timeslot % UInt32(config.value.epochLength) / UInt32(config.value.coreAssignmentRotationPeriod)

        return toCoreAssignment(source, n: n, max: UInt32(config.value.totalNumberOfCores))
    }

    public func requiredStorageKeys(extrinsic: ExtrinsicGuarantees) -> [any StateKey] {
        extrinsic.guarantees
            .flatMap(\.workReport.digests)
            .map { StateKeys.ServiceAccountKey(index: $0.serviceIndex) }
    }

    public func update(
        config: ProtocolConfigRef,
        timeslot: TimeslotIndex,
        extrinsic: ExtrinsicGuarantees
    ) async throws(GuaranteeingError) -> (
        newReports: ConfigFixedSizeArray<
            ReportItem?,
            ProtocolConfig.TotalNumberOfCores
        >,
        reported: [WorkReport],
        reporters: [Ed25519PublicKey]
    ) {
        let coreAssignmentRotationPeriod = UInt32(config.value.coreAssignmentRotationPeriod)

        let currentCoreAssignment = getCoreAssignment(config: config, randomness: entropyPool.t2, timeslot: timeslot)
        let currentCoreKeys = withoutOffenders(keys: currentValidators.map(\.ed25519))

        let isEpochChanging = (timeslot % UInt32(config.value.epochLength)) < coreAssignmentRotationPeriod
        let previousRandomness = isEpochChanging ? entropyPool.t3 : entropyPool.t2
        let previousValidators = isEpochChanging ? previousValidators : currentValidators

        let previousCoreAssignment = getCoreAssignment(
            config: config,
            randomness: previousRandomness,
            timeslot: UInt32(max(0, Int(timeslot) - Int(coreAssignmentRotationPeriod)))
        )
        let previousCoreKeys = withoutOffenders(keys: previousValidators.map(\.ed25519))

        var workPackageHashes = Set<Data32>()

        var oldLookups = [Data32: Data32]()

        var reporters = Set<Ed25519PublicKey>()

        for guarantee in extrinsic.guarantees {
            var totalGasUsage = Gas(0)
            let report = guarantee.workReport

            guard guarantee.timeslot <= timeslot else {
                throw .futureReportSlot
            }

            oldLookups[report.packageSpecification.workPackageHash] = report.packageSpecification.segmentRoot

            for credential in guarantee.credential {
                let isCurrent = (guarantee.timeslot / coreAssignmentRotationPeriod) == (timeslot / coreAssignmentRotationPeriod)
                let keys = isCurrent ? currentCoreKeys : previousCoreKeys
                let key = keys[Int(credential.index)]
                let reportHash = report.hash()
                workPackageHashes.insert(report.packageSpecification.workPackageHash)
                let payload = SigningContext.guarantee + reportHash.data
                let pubkey = try Result(catching: { try Ed25519.PublicKey(from: key) })
                    .mapError { _ in GuaranteeingError.invalidPublicKey }
                    .get()
                guard pubkey.verify(signature: credential.signature, message: payload) else {
                    throw .invalidGuaranteeSignature
                }

                let coreAssignment = isCurrent ? currentCoreAssignment : previousCoreAssignment
                guard coreAssignment[Int(credential.index)] == report.coreIndex else { // TODO: it should accepts the last core index?
                    throw .invalidGuaranteeCore
                }

                reporters.insert(key)
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

            for digest in report.digests {
                guard let acc = try? await serviceAccount(index: digest.serviceIndex) else {
                    throw .invalidServiceIndex
                }

                guard acc.codeHash == digest.codeHash else {
                    throw .invalidResultCodeHash
                }

                guard digest.gasLimit >= acc.minAccumlateGas else {
                    throw .invalidServiceGas
                }

                totalGasUsage += digest.gasLimit
            }

            guard totalGasUsage <= config.value.workReportAccumulationGas else {
                throw .outOfGas
            }
        }

        let recentWorkPackageHashes: Set<Data32> = Set(recentHistory.items.flatMap(\.lookup.keys))
        let accumulateHistoryReports = Set(accumulationHistory.array.flatMap(\.array))
        let accumulateQueueReports = Set(accumulationQueue.array.flatMap(\.self)
            .flatMap(\.workReport.refinementContext.prerequisiteWorkPackages))
        let pendingWorkReportHashes = Set(reports.array.flatMap { $0?.workReport.refinementContext.prerequisiteWorkPackages ?? [] })
        let pipelinedWorkReportHashes = recentWorkPackageHashes.union(accumulateHistoryReports).union(accumulateQueueReports)
            .union(pendingWorkReportHashes)
        guard pipelinedWorkReportHashes.isDisjoint(with: workPackageHashes) else {
            throw .duplicatedWorkPackage
        }

        for item in recentHistory.items {
            oldLookups.merge(item.lookup, uniquingKeysWith: { _, new in new })
        }

        for guarantee in extrinsic.guarantees {
            let report = guarantee.workReport
            let context = report.refinementContext
            let history = recentHistory.items.first { $0.headerHash == context.anchor.headerHash }
            guard let history else {
                throw .invalidContext
            }
            guard context.anchor.stateRoot == history.stateRoot else {
                throw .invalidContext
            }
            guard context.anchor.beefyRoot == history.superPeak else {
                throw .invalidContext
            }
            guard context.lookupAnchor.timeslot >= Int64(timeslot) - Int64(config.value.maxLookupAnchorAge) else {
                throw .invalidContext
            }

            for prerequisiteWorkPackage in context.prerequisiteWorkPackages.union(report.lookup.keys) {
                guard recentWorkPackageHashes.contains(prerequisiteWorkPackage) ||
                    workPackageHashes.contains(prerequisiteWorkPackage)
                else {
                    throw .prerequisiteNotFound
                }
            }

            for (hash, root) in report.lookup {
                guard oldLookups[hash] == root else {
                    throw .invalidSegmentLookup
                }
            }
        }

        var newReports = reports
        var reported = [WorkReport]()

        for guarantee in extrinsic.guarantees {
            let report = guarantee.workReport
            let coreIndex = Int(report.coreIndex)
            newReports[coreIndex] = ReportItem(
                workReport: report,
                timeslot: timeslot
            )
            reported.append(report)
        }

        reported.sort { $0.packageSpecification.workPackageHash < $1.packageSpecification.workPackageHash }
        let reportersArr = Array(reporters).sorted()

        return (newReports, reported, reportersArr)
    }
}
