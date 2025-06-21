import Codec
import TracingUtils
import Utils

private let logger = Logger(label: "Accumulation")

public enum AccumulationError: Error {
    case invalidServiceIndex
    case duplicatedNewService
    case duplicatedContributionToService
    case duplicatedRemovedService
}

public struct AccumulationQueueItem: Sendable, Equatable, Codable {
    public var workReport: WorkReport
    @CodingAs<SortedSet<Data32>> public var dependencies: Set<Data32>

    public init(workReport: WorkReport, dependencies: Set<Data32>) {
        self.workReport = workReport
        self.dependencies = dependencies
    }
}

// accumulation output pairing
public struct Commitment: Hashable {
    public var serviceIndex: ServiceIndex
    public var hash: Data32

    public init(service: ServiceIndex, hash: Data32) {
        serviceIndex = service
        self.hash = hash
    }
}

/// outer accumulation function ∆+ output
public struct AccumulationOutput {
    // number of work results accumulated
    public var numAccumulated: Int
    public var state: AccumulateState
    public var transfers: [DeferredTransfers]
    public var commitments: Set<Commitment>
    public var gasUsed: [(seriveIndex: ServiceIndex, gas: Gas)]
}

/// parallelized accumulation function ∆* output
public struct ParallelAccumulationOutput {
    public var state: AccumulateState
    public var transfers: [DeferredTransfers]
    public var commitments: Set<Commitment>
    public var gasUsed: [(seriveIndex: ServiceIndex, gas: Gas)]
}

/// single-service accumulation function ∆1 output
public typealias SingleAccumulationOutput = AccumulationResult

public struct ServicePreimagePair: Hashable {
    public var serviceIndex: ServiceIndex
    public var preimage: Data

    public init(service: ServiceIndex, preimage: Data) {
        serviceIndex = service
        self.preimage = preimage
    }
}

public struct AccumulationResult {
    // o
    public var state: AccumulateState
    // t
    public var transfers: [DeferredTransfers]
    // b
    public var commitment: Data32?
    // u
    public var gasUsed: Gas
    // p
    public var provide: Set<ServicePreimagePair>
}

public struct AccountChanges {
    public var newAccounts: [ServiceIndex: ServiceAccount]
    public var altered: Set<ServiceIndex>
    public var alterations: [(ServiceAccountsMutRef) -> Void]
    public var removed: Set<ServiceIndex>

    public init() {
        newAccounts = [:]
        alterations = []
        altered = []
        removed = []
    }

    public mutating func addAlteration(index: ServiceIndex, _ alteration: @escaping (ServiceAccountsMutRef) -> Void) {
        alterations.append(alteration)
        altered.insert(index)
    }

    public func apply(to accounts: ServiceAccountsMutRef) {
        for (index, account) in newAccounts {
            accounts.addNew(serviceAccount: index, account: account)
        }
        for index in removed {
            accounts.remove(serviceAccount: index)
        }
        for alteration in alterations {
            alteration(accounts)
        }
    }

    public mutating func checkAndMerge(with other: AccountChanges) throws(AccumulationError) {
        guard Set(newAccounts.keys).isDisjoint(with: other.newAccounts.keys) else {
            logger.debug("new accounts have duplicates, self: \(newAccounts.keys), other: \(other.newAccounts.keys)")
            throw .duplicatedNewService
        }
        guard altered.isDisjoint(with: other.altered) else {
            logger.debug("altered accounts have duplicates, self: \(altered), other: \(other.altered)")
            throw .duplicatedContributionToService
        }
        guard removed.isDisjoint(with: other.removed) else {
            logger.debug("removed accounts have duplicates, self: \(removed), other: \(other.removed)")
            throw .duplicatedRemovedService
        }

        for (index, account) in other.newAccounts {
            newAccounts[index] = account
        }
        altered.formUnion(other.altered)
        removed.formUnion(other.removed)
    }
}

public protocol Accumulation: ServiceAccounts {
    var timeslot: TimeslotIndex { get }
    var privilegedServices: PrivilegedServices { get set }
    var validatorQueue: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    > { get set }
    var authorizationQueue: ConfigFixedSizeArray<
        ConfigFixedSizeArray<
            Data32,
            ProtocolConfig.MaxAuthorizationsQueueItems
        >,
        ProtocolConfig.TotalNumberOfCores
    > { get set }
    var accumulationQueue: StateKeys.AccumulationQueueKey.Value { get set }
    var accumulationHistory: StateKeys.AccumulationHistoryKey.Value { get set }
}

public typealias AccumulationStats = [ServiceIndex: (Gas, UInt32)]
public typealias TransfersStats = [ServiceIndex: (UInt32, Gas)]

extension Accumulation {
    /// single-service accumulate function ∆1
    private mutating func singleAccumulate(
        config: ProtocolConfigRef,
        state: AccumulateState,
        workReports: [WorkReport],
        service: ServiceIndex,
        privilegedGas: [ServiceIndex: Gas],
        timeslot: TimeslotIndex
    ) async throws -> SingleAccumulationOutput {
        var gas = Gas(0)
        var arguments: [OperandTuple] = []

        gas += privilegedGas[service] ?? Gas(0)

        for report in workReports {
            for digest in report.digests where digest.serviceIndex == service {
                gas += digest.gasLimit
                arguments.append(OperandTuple(
                    packageHash: report.packageSpecification.workPackageHash,
                    segmentRoot: report.packageSpecification.segmentRoot,
                    authorizerHash: report.authorizerHash,
                    payloadHash: digest.payloadHash,
                    gasLimit: digest.gasLimit,
                    workResult: digest.result,
                    authorizerTrace: report.authorizerTrace,
                ))
            }
        }

        logger.debug("[single] accumulate arguments: \(arguments)")

        let result = try await accumulate(
            config: config,
            state: state,
            serviceIndex: service,
            gas: gas,
            arguments: arguments,
            timeslot: timeslot
        )

        logger.debug("[single] accumulate result: gasUsed=\(result.gasUsed), commitment=\(String(describing: result.commitment))")

        return result
    }

    /// parallelized accumulate function ∆*
    private mutating func parallelizedAccumulate(
        config: ProtocolConfigRef,
        state: AccumulateState,
        workReports: [WorkReport],
        privilegedGas: [ServiceIndex: Gas],
        timeslot: TimeslotIndex
    ) async throws -> ParallelAccumulationOutput {
        var services = [ServiceIndex]()
        var gasUsed: [(seriveIndex: ServiceIndex, gas: Gas)] = []
        var transfers: [DeferredTransfers] = []
        var commitments = Set<Commitment>()
        var newPrivilegedServices: PrivilegedServices?
        var newValidatorQueue: ConfigFixedSizeArray<
            ValidatorKey, ProtocolConfig.TotalNumberOfValidators
        >?
        var newAuthorizationQueue: ConfigFixedSizeArray<
            ConfigFixedSizeArray<
                Data32,
                ProtocolConfig.MaxAuthorizationsQueueItems
            >,
            ProtocolConfig.TotalNumberOfCores
        >?
        var overallAccountChanges = AccountChanges()

        for report in workReports {
            for digest in report.digests {
                services.append(digest.serviceIndex)
            }
        }

        for service in privilegedGas.keys {
            services.append(service)
        }

        logger.debug("[parallel] services to accumulate: \(services)")

        var accountsRef = ServiceAccountsMutRef(state.accounts.value)
        var servicePreimageSet = Set<ServicePreimagePair>()

        for service in services {
            let singleOutput = try await singleAccumulate(
                config: config,
                state: AccumulateState(
                    accounts: accountsRef,
                    validatorQueue: state.validatorQueue,
                    authorizationQueue: state.authorizationQueue,
                    privilegedServices: state.privilegedServices,
                    entropy: state.entropy
                ),
                workReports: workReports,
                service: service,
                privilegedGas: privilegedGas,
                timeslot: timeslot
            )
            gasUsed.append((service, singleOutput.gasUsed))

            if let commitment = singleOutput.commitment {
                commitments.insert(Commitment(service: service, hash: commitment))
            }

            for transfer in singleOutput.transfers {
                transfers.append(transfer)
            }

            servicePreimageSet.formUnion(singleOutput.provide)

            switch service {
            case privilegedServices.blessed:
                newPrivilegedServices = singleOutput.state.privilegedServices
            case privilegedServices.assign:
                newAuthorizationQueue = singleOutput.state.authorizationQueue
            case privilegedServices.designate:
                newValidatorQueue = singleOutput.state.validatorQueue
            default:
                break
            }

            accountsRef = singleOutput.state.accounts
            try overallAccountChanges.checkAndMerge(with: accountsRef.changes)
            accountsRef.clearRecordedChanges()
        }

        try await preimageIntegration(
            servicePreimageSet: servicePreimageSet,
            accounts: accountsRef,
            timeslot: timeslot
        )

        return ParallelAccumulationOutput(
            state: AccumulateState(
                accounts: accountsRef,
                validatorQueue: newValidatorQueue ?? validatorQueue,
                authorizationQueue: newAuthorizationQueue ?? authorizationQueue,
                privilegedServices: newPrivilegedServices ?? privilegedServices,
                entropy: state.entropy
            ),
            transfers: transfers,
            commitments: commitments,
            gasUsed: gasUsed
        )
    }

    /// outer accumulate function ∆+
    private mutating func outerAccumulate(
        config: ProtocolConfigRef,
        state: AccumulateState,
        workReports: [WorkReport],
        privilegedGas: [ServiceIndex: Gas],
        gasLimit: Gas,
        timeslot: TimeslotIndex
    ) async throws -> AccumulationOutput {
        var i = 0
        var sumGasRequired = Gas(0)

        for report in workReports {
            var canAccumulate = true
            for digest in report.digests {
                if digest.gasLimit + sumGasRequired > gasLimit {
                    canAccumulate = false
                    break
                }
                sumGasRequired += digest.gasLimit
            }
            i += canAccumulate ? 1 : 0
        }

        if i == 0 {
            return AccumulationOutput(
                numAccumulated: 0,
                state: state,
                transfers: [],
                commitments: Set(),
                gasUsed: []
            )
        } else {
            logger.debug("[outer] can accumulate until index: \(i)")

            let parallelOutput = try await parallelizedAccumulate(
                config: config,
                state: state,
                workReports: Array(workReports[0 ..< i]),
                privilegedGas: privilegedGas,
                timeslot: timeslot
            )
            let outerOutput = try await outerAccumulate(
                config: config,
                state: parallelOutput.state,
                workReports: Array(workReports[i ..< workReports.count]),
                privilegedGas: [:],
                gasLimit: gasLimit - parallelOutput.gasUsed.reduce(Gas(0)) { $0 + $1.gas },
                timeslot: timeslot
            )
            return AccumulationOutput(
                numAccumulated: i + outerOutput.numAccumulated,
                state: outerOutput.state,
                transfers: parallelOutput.transfers + outerOutput.transfers,
                commitments: parallelOutput.commitments.union(outerOutput.commitments),
                gasUsed: parallelOutput.gasUsed + outerOutput.gasUsed
            )
        }
    }

    // P: preimage integration function
    private func preimageIntegration(
        servicePreimageSet: Set<ServicePreimagePair>,
        accounts: ServiceAccountsMutRef,
        timeslot: TimeslotIndex
    ) async throws {
        for item in servicePreimageSet {
            let serviceIndex = item.serviceIndex
            let preimage = item.preimage
            let preimageHash = Blake2b256.hash(preimage)
            guard let preimageInfo = try await accounts.value.get(
                serviceAccount: serviceIndex,
                preimageHash: preimageHash,
                length: UInt32(preimage.count)
            ) else {
                continue
            }

            if preimageInfo.isEmpty {
                accounts.set(serviceAccount: serviceIndex, preimageHash: preimageHash, length: UInt32(preimage.count), value: [timeslot])
                accounts.set(serviceAccount: serviceIndex, preimageHash: preimageHash, value: preimage)
            }
        }
    }

    // E: edit the accumulation queue items when some work reports are accumulated
    private func editQueue(items: inout [AccumulationQueueItem], accumulatedPackages: Set<Data32>) {
        items = items.filter { !accumulatedPackages.contains($0.workReport.packageSpecification.workPackageHash) }

        for i in items.indices {
            items[i].dependencies.subtract(accumulatedPackages)
        }
    }

    // Q: provides the sequence of work-reports which are accumulatable given queue items
    private func getAccumulatables(items: inout [AccumulationQueueItem]) -> [WorkReport] {
        let noDepsReports = items.filter(\.dependencies.isEmpty).map(\.workReport)
        if noDepsReports.isEmpty {
            return []
        } else {
            editQueue(items: &items, accumulatedPackages: Set(noDepsReports.map(\.packageSpecification.workPackageHash)))
            return noDepsReports + getAccumulatables(items: &items)
        }
    }

    // newly available work-reports, W, are partitioned into two sequences based on the condition of having zero prerequisite work-reports
    private func partitionWorkReports(
        availableReports: [WorkReport]
    ) -> (zeroPrereqReports: [WorkReport], newQueueItems: [AccumulationQueueItem]) {
        let zeroPrereqReports = availableReports.filter { report in
            report.refinementContext.prerequisiteWorkPackages.isEmpty && report.lookup.isEmpty
        }

        let queuedReports = availableReports.filter { !zeroPrereqReports.contains($0) }

        var newQueueItems: [AccumulationQueueItem] = []
        for report in queuedReports {
            newQueueItems.append(.init(
                workReport: report,
                dependencies: report.refinementContext.prerequisiteWorkPackages.union(report.lookup.keys)
            ))
        }

        editQueue(
            items: &newQueueItems,
            accumulatedPackages: Set(accumulationHistory.array.reduce(into: Set<Data32>()) { $0.formUnion($1.array) })
        )

        return (zeroPrereqReports, newQueueItems)
    }

    // get all the work reports that can be accumulated in this block
    private func getAllAccumulatableReports(
        availableReports: [WorkReport],
        index: Int
    ) -> (accumulatableReports: [WorkReport], newQueueItems: [AccumulationQueueItem]) {
        let (zeroPrereqReports, newQueueItems) = partitionWorkReports(availableReports: availableReports)

        let rightQueueItems = accumulationQueue.array[index...]
        let leftQueueItems = accumulationQueue.array[0 ..< index]
        var allQueueItems = rightQueueItems.flatMap(\.self) + leftQueueItems.flatMap(\.self) + newQueueItems

        editQueue(items: &allQueueItems, accumulatedPackages: Set(zeroPrereqReports.map(\.packageSpecification.workPackageHash)))

        return (zeroPrereqReports + getAccumulatables(items: &allQueueItems), newQueueItems)
    }

    // accumulate execution
    private mutating func execution(
        config: ProtocolConfigRef,
        workReports: [WorkReport],
        state: AccumulateState,
        timeslot: TimeslotIndex
    ) async throws -> AccumulationOutput {
        let sumPrevilegedGas = privilegedServices.basicGas.values.reduce(Gas(0)) { $0 + $1.value }
        let minTotalGas = config.value.workReportAccumulationGas * Gas(config.value.totalNumberOfCores) + sumPrevilegedGas
        let gasLimit = max(config.value.totalAccumulationGas, minTotalGas)

        return try await outerAccumulate(
            config: config,
            state: state,
            workReports: workReports,
            privilegedGas: privilegedServices.basicGas,
            gasLimit: gasLimit,
            timeslot: timeslot
        )
    }

    /// Accumulate execution, state integration and deferred transfers
    ///
    /// Return accumulation-result merkle tree root
    public mutating func update(
        config: ProtocolConfigRef,
        availableReports: [WorkReport],
        timeslot: TimeslotIndex,
        prevTimeslot: TimeslotIndex,
        entropy: Data32
    ) async throws -> (root: Data32, AccumulationStats, TransfersStats) {
        let index = Int(timeslot) %% config.value.epochLength

        logger.debug("available reports (\(availableReports.count)): \(availableReports.map(\.packageSpecification.workPackageHash))")

        var (accumulatableReports, newQueueItems) = getAllAccumulatableReports(
            availableReports: availableReports,
            index: index
        )

        logger.debug("accumulatable reports: \(accumulatableReports.map(\.packageSpecification.workPackageHash))")

        let accountsMutRef = ServiceAccountsMutRef(self)

        let initialAccState = AccumulateState(
            accounts: accountsMutRef,
            validatorQueue: validatorQueue,
            authorizationQueue: authorizationQueue,
            privilegedServices: privilegedServices,
            entropy: entropy
        )

        let accumulateOutput = try await execution(
            config: config,
            workReports: accumulatableReports,
            state: initialAccState,
            timeslot: timeslot
        )

        authorizationQueue = accumulateOutput.state.authorizationQueue
        validatorQueue = accumulateOutput.state.validatorQueue
        privilegedServices = accumulateOutput.state.privilegedServices

        // transfers execution + transfers statistics
        var transferGroups = [ServiceIndex: [DeferredTransfers]]()
        var transfersStats = TransfersStats()
        for transfer in accumulateOutput.transfers {
            transferGroups[transfer.destination, default: []].append(transfer)
        }
        for (service, transfers) in transferGroups.sorted(by: { $0.key < $1.key }) {
            let gasUsed = try await onTransfer(
                config: config,
                serviceIndex: service,
                serviceAccounts: accountsMutRef,
                timeslot: timeslot,
                entropy: entropy,
                transfers: transfers
            )
            let count = UInt32(transfers.count)
            if count == 0 { continue }
            transfersStats[service] = (count, gasUsed)
        }

        self = accountsMutRef.value as! Self

        // update accumulation history
        let accumulated = accumulatableReports[0 ..< accumulateOutput.numAccumulated]
        let newHistoryItem = Set(accumulated.map(\.packageSpecification.workPackageHash))
        for i in 0 ..< config.value.epochLength {
            if i == config.value.epochLength - 1 {
                accumulationHistory[i] = .init(newHistoryItem)
            } else {
                accumulationHistory[i] = accumulationHistory[i + 1]
            }
        }

        // update accumulation queue
        for i in 0 ..< config.value.epochLength {
            let queueIdx = (index - i) %% config.value.epochLength
            if i == 0 {
                editQueue(items: &newQueueItems, accumulatedPackages: newHistoryItem)
                accumulationQueue[queueIdx] = newQueueItems
            } else if i >= 1, i < timeslot - prevTimeslot {
                accumulationQueue[queueIdx] = []
            } else {
                editQueue(items: &accumulationQueue[queueIdx], accumulatedPackages: newHistoryItem)
            }
        }

        let commitmentsSorted = accumulateOutput.commitments.sorted { $0.serviceIndex < $1.serviceIndex }
        logger.debug("accumulation commitments sorted: \(commitmentsSorted)")

        // get accumulate root
        let nodes = try commitmentsSorted.map { try JamEncoder.encode($0.serviceIndex) + JamEncoder.encode($0.hash) }

        logger.debug("accumulation commitments encoded: \(nodes.map { $0.toHexString() })")

        let root = Merklization.binaryMerklize(nodes, hasher: Keccak.self)

        logger.debug("accumulation root: \(root)")

        // get accumulation statistics
        var accumulateStats = AccumulationStats()
        for (service, _) in accumulateOutput.gasUsed {
            if accumulateStats[service] != nil { continue }

            let num = accumulated.filter { report in
                report.digests.contains { $0.serviceIndex == service }
            }.count

            if num == 0 { continue }

            let gasUsed = accumulateOutput.gasUsed
                .filter { $0.seriveIndex == service }
                .reduce(Gas(0)) { $0 + $1.gas }

            accumulateStats[service] = (gasUsed, UInt32(num))
        }

        return (root, accumulateStats, transfersStats)
    }
}
