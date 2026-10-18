import Codec
import Utils

private struct AncestryLookupKey: Hashable {
    let timeslot: TimeslotIndex
    let headerHash: Data32
}

public enum GuaranteeingError: Error {
    case invalidGuaranteeSignature
    case invalidGuaranteeCore
    case coreNotAvailable
    case invalidReportAuthorizer
    case invalidServiceIndex
    case missingWorkResults
    case outOfGas
    case invalidContext
    case duplicatedWorkPackage
    case prerequisiteNotFound
    case invalidResultCodeHash
    case invalidServiceGas
    case invalidPublicKey
    case invalidSegmentLookup
    case futureReportSlot
    case refineLoadTooHigh
    case badExportsCount
    case bundleTooBig
    case authGasTooHigh
    case badAnchorSlot
    case badErasureShards
}

public protocol Guaranteeing {
    var entropyPool: EntropyPool { get }
    var currentValidators: ValidatorKeys { get }
    var previousValidators: ValidatorKeys { get }
    var availabilityAssignments: ConfigFixedSizeArray<
        ReportItem?,
        ProtocolConfig.TotalNumberOfCores,
    > { get }
    var coreAuthorizationPool: ConfigFixedSizeArray<
        ConfigLimitedSizeArray<
            Data32,
            ProtocolConfig.Int0,
            ProtocolConfig.MaxAuthorizationsPoolItems,
        >,
        ProtocolConfig.TotalNumberOfCores,
    > { get }
    var recentHistory: RecentHistory { get }
    var offenders: Set<Ed25519PublicKey> { get }
    var accumulationQueue: ConfigFixedSizeArray<
        [AccumulationQueueItem],
        ProtocolConfig.EpochLength,
    > { get }
    var accumulationHistory: ConfigFixedSizeArray<
        SortedUniqueArray<Data32>,
        ProtocolConfig.EpochLength,
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

    public func getCoreAssignment(config: ProtocolConfigRef, randomness: Data32, timeslot: TimeslotIndex, validatorCount: Int? = nil) -> [CoreIndex] {
        let count = validatorCount ?? currentValidators.count
        var source = Array(repeating: UInt32(0), count: count)
        for i in 0 ..< count {
            source[i] = UInt32(i / 3)
        }
        source.shuffle(randomness: randomness)

        let n = timeslot % UInt32(config.value.epochLength) / UInt32(config.value.coreAssignmentRotationPeriod)

        return toCoreAssignment(source, n: n, max: UInt32(count / 3))
    }

    public func requiredStorageKeys(extrinsic: ExtrinsicGuarantees) -> [any StateKey] {
        var serviceIndices: [ServiceIndex] = []
        serviceIndices.reserveCapacity(extrinsic.guarantees.reduce(0) { $0 + $1.workReport.digests.count })

        for guarantee in extrinsic.guarantees {
            for digest in guarantee.workReport.digests where !serviceIndices.contains(digest.serviceIndex) {
                serviceIndices.append(digest.serviceIndex)
            }
        }

        var keys: [any StateKey] = []
        keys.reserveCapacity(serviceIndices.count)
        for serviceIndex in serviceIndices {
            keys.append(StateKeys.ServiceAccountKey(index: serviceIndex))
        }
        return keys
    }

    private func pipelinedWorkReportHashes(recentWorkPackageHashes: Set<Data32>) -> Set<Data32> {
        var hashes = recentWorkPackageHashes

        for history in accumulationHistory {
            hashes.formUnion(history.array)
        }
        for queue in accumulationQueue {
            for item in queue {
                hashes.formUnion(item.workReport.refinementContext.prerequisiteWorkPackages)
            }
        }
        for report in availabilityAssignments {
            if let report {
                hashes.formUnion(report.workReport.refinementContext.prerequisiteWorkPackages)
            }
        }

        return hashes
    }

    public func validateGuarantees(
        config: ProtocolConfigRef,
        extrinsic: ExtrinsicGuarantees,
    ) async throws(GuaranteeingError) {
        var firstCachedAccount: (ServiceIndex, ServiceAccountDetails)?
        var additionalCachedAccounts: [(ServiceIndex, ServiceAccountDetails)] = []

        for guarantee in extrinsic.guarantees {
            var accumulationGasRemaining = config.value.workReportAccumulationGas
            let report = guarantee.workReport

            guard !report.digests.isEmpty else {
                throw .missingWorkResults
            }

            for digest in report.digests {
                let acc: ServiceAccountDetails
                if let cached = firstCachedAccount, cached.0 == digest.serviceIndex {
                    acc = cached.1
                } else if let cached = additionalCachedAccounts.first(where: { $0.0 == digest.serviceIndex })?.1 {
                    acc = cached
                } else {
                    guard let fetched = try? await serviceAccount(index: digest.serviceIndex) else {
                        throw .invalidServiceIndex
                    }
                    if firstCachedAccount == nil {
                        firstCachedAccount = (digest.serviceIndex, fetched)
                    } else {
                        additionalCachedAccounts.append((digest.serviceIndex, fetched))
                    }
                    acc = fetched
                }

                guard acc.codeHash == digest.codeHash else {
                    throw .invalidResultCodeHash
                }

                guard digest.gasLimit >= acc.minItemGas else {
                    throw .invalidServiceGas
                }

                guard digest.gasLimit <= accumulationGasRemaining else {
                    throw .outOfGas
                }
                accumulationGasRemaining -= digest.gasLimit
            }

            // Report loads must fit the corresponding work-package limits.
            // Subtract from bounded budgets so malicious sums cannot overflow.
            var refineGas = config.value.workPackageRefineGas.value
            var imports = UInt(config.value.maxWorkPackageImports)
            var exports = UInt(config.value.maxWorkPackageExports)
            var extrinsics = UInt(config.value.maxWorkPackageExtrinsics)
            var inputBytes = UInt(config.value.maxEncodedWorkPackageSize)
            let footprint = UInt(config.value.segmentFootprint)
            for digest in report.digests {
                guard digest.gasUsed <= refineGas,
                      digest.importsCount <= imports,
                      digest.exportsCount <= exports,
                      digest.extrinsicsCount <= extrinsics,
                      digest.extrinsicsSize <= inputBytes
                else {
                    throw .refineLoadTooHigh
                }
                refineGas -= UInt64(digest.gasUsed)
                imports -= digest.importsCount
                exports -= digest.exportsCount
                extrinsics -= digest.extrinsicsCount
                inputBytes -= digest.extrinsicsSize
                let (importBytes, overflow) = digest.importsCount.multipliedReportingOverflow(by: footprint)
                guard !overflow, importBytes <= inputBytes else {
                    throw .refineLoadTooHigh
                }
                inputBytes -= importBytes
            }
            guard UInt(report.packageSpecification.segmentCount) == UInt(config.value.maxWorkPackageExports) - exports else {
                throw .badExportsCount
            }
            guard report.packageSpecification.length <= config.value.maxWorkBundleSize else {
                throw .bundleTooBig
            }
            guard report.authGasUsed <= config.value.workPackageIsAuthorizedGas.value else {
                throw .authGasTooHigh
            }
        }
    }

    public func update(
        config: ProtocolConfigRef,
        timeslot: TimeslotIndex,
        extrinsic: ExtrinsicGuarantees,
        ancestry: ConfigLimitedSizeArray<AncestryItem, ProtocolConfig.Int0, ProtocolConfig.MaxLookupAnchorAge>?,
        parentStateRoot: (hash: Data32, root: Data32)? = nil,
    ) async throws(GuaranteeingError) -> (
        newAvailabilityAssignments: ConfigFixedSizeArray<
            ReportItem?,
            ProtocolConfig.TotalNumberOfCores,
        >,
        reported: [WorkReport],
        reporters: [Ed25519PublicKey],
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
            timeslot: UInt32(max(0, Int(timeslot) - Int(coreAssignmentRotationPeriod))),
            validatorCount: previousValidators.count,
        )
        let previousCoreKeys = withoutOffenders(keys: previousValidators.map(\.ed25519))

        var workPackageHashes = Set<Data32>()

        var oldLookups = [Data32: Data32]()

        var reporters = Set<Ed25519PublicKey>()
        var recentHistoryByHeaderHash = [Data32: RecentHistory.HistoryItem]()

        for item in recentHistory.items {
            oldLookups.merge(item.lookup, uniquingKeysWith: { _, new in new })
            if recentHistoryByHeaderHash[item.headerHash] == nil {
                recentHistoryByHeaderHash[item.headerHash] = item
            }
        }

        let ancestryLookup = ancestry.map {
            Set($0.array.map { AncestryLookupKey(timeslot: $0.timeslot, headerHash: $0.headerHash) })
        }
        var ancestryStateRoots = ancestry.map { items in
            Dictionary(items.array.map { ($0.parentHash, $0.priorStateRoot) }, uniquingKeysWith: { first, _ in first })
        }
        // The current header is also in GP's ancestor set and commits to its
        // parent's posterior state, before it is appended to retained ancestry.
        if let parentStateRoot {
            ancestryStateRoots?[parentStateRoot.hash] = parentStateRoot.root
        }

        for guarantee in extrinsic.guarantees {
            let report = guarantee.workReport

            guard report.packageSpecification.erasureShards == currentValidators.count else {
                throw .badErasureShards
            }
            guard guarantee.timeslot <= timeslot else {
                throw .futureReportSlot
            }

            // Check that the guarantee's rotation period is not too old
            let guaranteeRotationPeriod = guarantee.timeslot / coreAssignmentRotationPeriod
            let currentRotationPeriod = timeslot / coreAssignmentRotationPeriod
            let minimumAcceptablePeriod = currentRotationPeriod > 0 ? currentRotationPeriod - 1 : 0
            guard guaranteeRotationPeriod >= minimumAcceptablePeriod else {
                throw GuaranteeingError.coreNotAvailable
            }

            oldLookups[report.packageSpecification.workPackageHash] = report.packageSpecification.segmentRoot
            workPackageHashes.insert(report.packageSpecification.workPackageHash)

            let isCurrent = (guarantee.timeslot / coreAssignmentRotationPeriod) == (timeslot / coreAssignmentRotationPeriod)
            let keys = isCurrent ? currentCoreKeys : previousCoreKeys
            let coreAssignment = isCurrent ? currentCoreAssignment : previousCoreAssignment
            let reportHash = report.hash()
            let payload = SigningContext.guarantee + reportHash.data

            guard report.coreIndex < currentValidators.count / 3 else {
                throw .invalidGuaranteeCore
            }

            for credential in guarantee.credential {
                guard Int(credential.index) < keys.count else {
                    throw .invalidGuaranteeCore
                }
                let key = keys[Int(credential.index)]
                let pubkey = try Result(catching: { try Ed25519.PublicKey(from: key) })
                    .mapError { _ in GuaranteeingError.invalidPublicKey }
                    .get()
                guard pubkey.verify(signature: credential.signature, message: payload) else {
                    throw .invalidGuaranteeSignature
                }

                // Verify credential's core index matches report's core index
                // Note: This validation ensures the credential is for the correct core.
                // Future consideration: Should this accept the last core index for edge cases?
                guard coreAssignment[Int(credential.index)] == report.coreIndex else {
                    throw .invalidGuaranteeCore
                }

                reporters.insert(key)
            }

            let coreIndex = Int(report.coreIndex)

            guard availabilityAssignments[coreIndex] == nil else {
                throw .coreNotAvailable
            }

            guard coreAuthorizationPool[coreIndex].contains(report.authorizerHash) else {
                throw .invalidReportAuthorizer
            }
        }

        let recentWorkPackageHashes: Set<Data32> = Set(recentHistory.items.flatMap(\.lookup.keys))
        let pipelinedWorkReportHashes = pipelinedWorkReportHashes(recentWorkPackageHashes: recentWorkPackageHashes)
        guard pipelinedWorkReportHashes.isDisjoint(with: workPackageHashes) else {
            throw .duplicatedWorkPackage
        }

        for guarantee in extrinsic.guarantees {
            let report = guarantee.workReport
            let context = report.refinementContext
            let history = recentHistoryByHeaderHash[context.anchor.headerHash]
            guard let history else {
                throw .invalidContext
            }
            guard context.anchor.stateRoot == history.stateRoot else {
                throw .invalidContext
            }
            guard context.anchor.beefyRoot == history.superPeak else {
                throw .invalidContext
            }
            guard context.anchor.timeslot == history.timeslot else {
                throw .badAnchorSlot
            }
            guard context.lookupAnchor.timeslot >= Int64(timeslot) - Int64(config.value.maxLookupAnchorAge) else {
                throw .invalidContext
            }

            if let ancestryLookup {
                let lookupTimeslot = UInt32(context.lookupAnchor.timeslot)
                let lookupHeaderHash = context.lookupAnchor.headerHash

                guard ancestryLookup.contains(AncestryLookupKey(timeslot: lookupTimeslot, headerHash: lookupHeaderHash)) else {
                    throw .invalidContext
                }
                guard ancestryStateRoots?[lookupHeaderHash] == context.lookupAnchor.stateRoot else {
                    throw .invalidContext
                }
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

        var newAvailabilityAssignments = availabilityAssignments
        var reported = [WorkReport]()

        for guarantee in extrinsic.guarantees {
            let report = guarantee.workReport
            let coreIndex = Int(report.coreIndex)
            newAvailabilityAssignments[coreIndex] = ReportItem(
                guarantee: guarantee,
                timeslot: timeslot,
            )
            reported.append(report)
        }

        reported.sort { $0.packageSpecification.workPackageHash < $1.packageSpecification.workPackageHash }
        let reportersArr = Array(reporters).sorted()

        return (newAvailabilityAssignments, reported, reportersArr)
    }
}
