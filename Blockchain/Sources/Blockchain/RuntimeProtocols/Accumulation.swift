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
public struct Commitment: Hashable, Sendable, Equatable, Codable {
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
    public var commitments: Set<Commitment>
    public var gasUsed: [(serviceIndex: ServiceIndex, gas: Gas)]
}

/// parallelized accumulation function ∆* output
public struct ParallelAccumulationOutput {
    public var state: AccumulateState
    public var transfers: [DeferredTransfers]
    public var commitments: Set<Commitment>
    public var gasUsed: [(serviceIndex: ServiceIndex, gas: Gas)]
}

/// single-service accumulation function ∆1 output
public typealias SingleAccumulationOutput = AccumulationResult

public struct ServicePreimagePair: Hashable, Sendable {
    public var serviceIndex: ServiceIndex
    public var preimage: Data

    public init(service: ServiceIndex, preimage: Data) {
        serviceIndex = service
        self.preimage = preimage
    }
}

public struct AccumulationResult: Sendable {
    // e
    public var state: AccumulateState
    // t
    public var transfers: [DeferredTransfers]
    // y
    public var commitment: Data32?
    // u
    public var gasUsed: Gas
    // p
    public var provide: Set<ServicePreimagePair>
}

public struct AccountChanges: Sendable {
    public enum UpdateKind: Sendable {
        case newAccount(ServiceIndex, ServiceAccount)
        case removeAccount(ServiceIndex)
        case updateAccount(ServiceIndex, ServiceAccountDetails)
        case updateStorage(ServiceIndex, Data, Data?)
        case updatePreimage(ServiceIndex, Data32, Data?)
        case updatePreimageInfo(ServiceIndex, Data32, UInt32, StateKeys.ServiceAccountPreimageInfoKey.Value?)
    }

    // records for checking conflicts
    public var newAccounts: [ServiceIndex: ServiceAccount]
    public var altered: Set<ServiceIndex>
    public var removed: Set<ServiceIndex>

    // array for apply sequential updates
    public var updates: [UpdateKind]

    public init() {
        newAccounts = [:]
        altered = []
        removed = []
        updates = []
    }

    public mutating func addNewAccount(index: ServiceIndex, account: ServiceAccount) {
        newAccounts[index] = account
        updates.append(.newAccount(index, account))
    }

    public mutating func addRemovedAccount(index: ServiceIndex) {
        removed.insert(index)
        updates.append(.removeAccount(index))
    }

    public mutating func addAccountUpdate(index: ServiceIndex, account: ServiceAccountDetails) {
        altered.insert(index)
        updates.append(.updateAccount(index, account))
    }

    public mutating func addStorageUpdate(index: ServiceIndex, key: Data, value: Data?) {
        altered.insert(index)
        updates.append(.updateStorage(index, key, value))
    }

    public mutating func addPreimageUpdate(index: ServiceIndex, hash: Data32, value: Data?) {
        altered.insert(index)
        updates.append(.updatePreimage(index, hash, value))
    }

    public mutating func addPreimageInfoUpdate(
        index: ServiceIndex,
        hash: Data32,
        length: UInt32,
        value: StateKeys.ServiceAccountPreimageInfoKey.Value?
    ) {
        altered.insert(index)
        updates.append(.updatePreimageInfo(index, hash, length, value))
    }

    public func apply(to accounts: ServiceAccountsMutRef) async throws {
        for update in updates {
            switch update {
            case let .newAccount(index, account):
                try await accounts.addNew(serviceAccount: index, account: account)
            case let .removeAccount(index):
                try await accounts.remove(serviceAccount: index)
            case let .updateAccount(index, account):
                accounts.set(serviceAccount: index, account: account)
            case let .updateStorage(index, key, value):
                try await accounts.set(serviceAccount: index, storageKey: key, value: value)
            case let .updatePreimage(index, hash, value):
                accounts.set(serviceAccount: index, preimageHash: hash, value: value)
            case let .updatePreimageInfo(index, hash, length, value):
                try await accounts.set(serviceAccount: index, preimageHash: hash, length: length, value: value)
            }
        }
    }

    public mutating func checkAndMerge(with other: AccountChanges) throws(AccumulationError) {
        guard Set(newAccounts.keys).isDisjoint(with: other.newAccounts.keys) else {
            logger.debug("new accounts have duplicates, self: \(newAccounts.keys), other: \(other.newAccounts.keys)")
            throw .duplicatedNewService
        }
        guard altered.isDisjoint(with: other.altered) else {
            logger.debug("same service being altered in parallel, self: \(altered), other: \(other.altered)")
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
        updates.append(contentsOf: other.updates)
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

extension Accumulation {
    /// single-service accumulate function ∆1
    private static func singleAccumulate(
        config: ProtocolConfigRef,
        state: AccumulateState,
        transfers: [DeferredTransfers],
        workReports: [WorkReport],
        service: ServiceIndex,
        alwaysAcc: [ServiceIndex: Gas],
        timeslot: TimeslotIndex
    ) async throws -> (ServiceIndex, AccumulationResult) {
        var gas = Gas(0)
        var arguments: [AccumulationInput] = []

        gas += alwaysAcc[service] ?? Gas(0)

        for transfer in transfers where transfer.destination == service {
            gas += transfer.gasLimit
            // i_T
            arguments.append(AccumulationInput(deferredTransfers: transfer))
        }

        for report in workReports {
            for digest in report.digests where digest.serviceIndex == service {
                gas += digest.gasLimit
                // i_U
                arguments.append(AccumulationInput(operandTuple: OperandTuple(
                    packageHash: report.packageSpecification.workPackageHash,
                    segmentRoot: report.packageSpecification.segmentRoot,
                    authorizerHash: report.authorizerHash,
                    payloadHash: digest.payloadHash,
                    gasLimit: digest.gasLimit,
                    workResult: digest.result,
                    authorizerTrace: report.authorizerTrace,
                )))
            }
        }

        logger.debug("[∆1] service: \(service), arguments: \(arguments)")

        let result = try await accumulate(
            config: config,
            state: state,
            serviceIndex: service,
            gas: gas,
            arguments: arguments,
            timeslot: timeslot
        )

        logger.debug("[∆1] service: \(service), gasUsed: \(result.gasUsed), commitment: \(String(describing: result.commitment))")

        return (service, result)
    }

    /// parallelized accumulate function ∆*
    private func parallelizedAccumulate(
        config: ProtocolConfigRef,
        state: AccumulateState,
        transfers: [DeferredTransfers],
        workReports: [WorkReport],
        alwaysAcc: [ServiceIndex: Gas],
        timeslot: TimeslotIndex
    ) async throws -> ParallelAccumulationOutput {
        var services = [ServiceIndex]()
        var gasUsed: [(serviceIndex: ServiceIndex, gas: Gas)] = []
        var commitments = Set<Commitment>()
        var currentState = state
        var servicePreimageSet = Set<ServicePreimagePair>()

        // get services to accumulate
        for report in workReports {
            for digest in report.digests {
                services.append(digest.serviceIndex)
            }
        }
        for service in alwaysAcc.keys {
            services.append(service)
        }
        for service in transfers.map(\.destination) {
            services.append(service)
        }

        let uniqueServices = Set(services)
        logger.debug("[∆*] services to accumulate: \(Array(uniqueServices))")

        let batchState = currentState

        batchState.accounts.clearRecordedChanges()

        // parallel accumulate
        let batchResults = try await withThrowingTaskGroup(
            of: (ServiceIndex, AccumulationResult).self,
            returning: [(ServiceIndex, AccumulationResult)].self
        ) { group in
            for service in uniqueServices {
                group.addTask { [batchState] in
                    return try await Self.singleAccumulate(
                        config: config,
                        state: batchState.copy(),
                        transfers: transfers,
                        workReports: workReports,
                        service: service,
                        alwaysAcc: alwaysAcc,
                        timeslot: timeslot
                    )
                }
            }

            var results: [(ServiceIndex, AccumulationResult)] = []
            for try await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 }
        }

        // parallel batch results merging
        var batchAccountChanges = AccountChanges()
        var newTransfers: [DeferredTransfers] = []
        // initial privileged services
        let initialDelegator = currentState.delegator
        let initialRegistrar = currentState.registrar
        let initialAssigners = currentState.assigners
        for (service, singleOutput) in batchResults {
            // u
            gasUsed.append((service, singleOutput.gasUsed))

            // b
            if let commitment = singleOutput.commitment {
                commitments.insert(Commitment(service: service, hash: commitment))
            }

            // t'
            for transfer in singleOutput.transfers {
                newTransfers.append(transfer)
            }

            // collect preimages to integrate
            servicePreimageSet.formUnion(singleOutput.provide)

            // collect batch account changes
            try batchAccountChanges.checkAndMerge(with: singleOutput.state.accounts.changes)

            // a' - New assigners
            if let index = currentState.assigners.firstIndex(of: service) {
                var temp = currentState.assigners
                temp[index] = singleOutput.state.assigners[index]
                currentState.assigners = temp
            }
            // v' - New delegator
            if service == initialDelegator {
                currentState.delegator = singleOutput.state.delegator
            }
            // r' - New registrar
            if service == initialRegistrar {
                currentState.registrar = singleOutput.state.registrar
            }

            // i' - Current delegator service can update validator queue
            if service == privilegedServices.delegator {
                currentState.validatorQueue = singleOutput.state.validatorQueue
            }
            // q' - Current assigners update authorization queue
            if let index = privilegedServices.assigners.firstIndex(of: service) {
                currentState.authorizationQueue[index] = singleOutput.state.authorizationQueue[index]
            }
        }

        // manager's changes override service's changes
        if let managerResult = batchResults.first(where: { $0.0 == privilegedServices.manager })?.1 {
            // m' - manager always writes
            currentState.manager = managerResult.state.manager
            // z' - alwaysAcc always writes
            currentState.alwaysAcc = managerResult.state.alwaysAcc
            // a' - if manager changed assigners from initial, use manager's value
            if initialAssigners != managerResult.state.assigners {
                currentState.assigners = managerResult.state.assigners
            }
            // v' - if manager changed delegator from initial, use manager's value
            if initialDelegator != managerResult.state.delegator {
                currentState.delegator = managerResult.state.delegator
            }
            // r' - if manager changed registrar from initial, use manager's value
            if initialRegistrar != managerResult.state.registrar {
                currentState.registrar = managerResult.state.registrar
            }
        }

        // d'
        try await batchAccountChanges.apply(to: currentState.accounts) // (d U n) ∖ m
        try await preimageIntegration(
            servicePreimageSet: servicePreimageSet,
            accounts: currentState.accounts,
            timeslot: timeslot
        )

        return ParallelAccumulationOutput(
            state: currentState,
            transfers: newTransfers,
            commitments: commitments,
            gasUsed: gasUsed
        )
    }

    /// outer accumulate function ∆+
    private func outerAccumulate(
        config: ProtocolConfigRef,
        state: AccumulateState,
        transfers: [DeferredTransfers],
        workReports: [WorkReport],
        alwaysAcc: [ServiceIndex: Gas],
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
            if canAccumulate {
                i += 1
            } else {
                break
            }
        }

        let n = i + transfers.count + alwaysAcc.count

        if n == 0 {
            return AccumulationOutput(
                numAccumulated: 0,
                state: state,
                commitments: Set(),
                gasUsed: []
            )
        } else {
            logger.debug("[∆+] can accumulate until index: \(i)")

            let parallelOutput = try await parallelizedAccumulate(
                config: config,
                state: state,
                transfers: transfers,
                workReports: Array(workReports[0 ..< i]),
                alwaysAcc: alwaysAcc,
                timeslot: timeslot
            )
            let parallelGasUsed = parallelOutput.gasUsed.reduce(Gas(0)) { $0 + $1.gas }
            let transfersGas = transfers.reduce(Gas(0)) { $0 + $1.gasLimit }
            let outerOutput = try await outerAccumulate(
                config: config,
                state: parallelOutput.state,
                transfers: parallelOutput.transfers,
                workReports: Array(workReports[i ..< workReports.count]),
                alwaysAcc: [:],
                gasLimit: gasLimit + transfersGas - parallelGasUsed,
                timeslot: timeslot
            )
            return AccumulationOutput(
                numAccumulated: i + outerOutput.numAccumulated,
                state: outerOutput.state,
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
                try await accounts.set(
                    serviceAccount: serviceIndex,
                    preimageHash: preimageHash,
                    length: UInt32(preimage.count),
                    value: [timeslot]
                )
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
    private func execution(
        config: ProtocolConfigRef,
        workReports: [WorkReport],
        state: AccumulateState,
        timeslot: TimeslotIndex
    ) async throws -> AccumulationOutput {
        let sumPrivilegedGas = privilegedServices.alwaysAcc.values.reduce(Gas(0)) { $0 + $1.value }
        let minTotalGas = config.value.workReportAccumulationGas * Gas(config.value.totalNumberOfCores) + sumPrivilegedGas
        let gasLimit = max(config.value.totalAccumulationGas, minTotalGas)

        return try await outerAccumulate(
            config: config,
            state: state,
            transfers: [],
            workReports: workReports,
            alwaysAcc: privilegedServices.alwaysAcc,
            gasLimit: gasLimit,
            timeslot: timeslot
        )
    }

    /// Accumulate execution, state integration and deferred transfers
    public mutating func update(
        config: ProtocolConfigRef,
        availableReports: [WorkReport],
        timeslot: TimeslotIndex,
        prevTimeslot: TimeslotIndex,
        entropy: Data32
    ) async throws -> (root: Data32, [Commitment], AccumulationStats) {
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
            manager: privilegedServices.manager,
            assigners: privilegedServices.assigners,
            delegator: privilegedServices.delegator,
            registrar: privilegedServices.registrar,
            alwaysAcc: privilegedServices.alwaysAcc,
            entropy: entropy
        )

        let accumulateOutput = try await execution(
            config: config,
            workReports: accumulatableReports,
            state: initialAccState,
            timeslot: timeslot
        )

        self = accumulateOutput.state.accounts.value as! Self

        // update non-accounts state after accounts updated
        authorizationQueue = accumulateOutput.state.authorizationQueue
        validatorQueue = accumulateOutput.state.validatorQueue
        privilegedServices = PrivilegedServices(
            manager: accumulateOutput.state.manager,
            assigners: accumulateOutput.state.assigners,
            delegator: accumulateOutput.state.delegator,
            registrar: accumulateOutput.state.registrar,
            alwaysAcc: accumulateOutput.state.alwaysAcc
        )

        // update accumulation history
        let accumulated: [WorkReport] = Array(accumulatableReports[0 ..< accumulateOutput.numAccumulated])
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

        // get accumulation statistics
        var accumulateStats = AccumulationStats()
        for (service, _) in accumulateOutput.gasUsed {
            if accumulateStats[service] != nil { continue }

            let digests = accumulated.compactMap(\.digests).flatMap(\.self)
            let num = digests.filter { $0.serviceIndex == service }.count
            let gasUsed = accumulateOutput.gasUsed
                .filter { $0.serviceIndex == service }
                .reduce(Gas(0)) { $0 + $1.gas }
            if Int(gasUsed.value) + num == 0 { continue }

            accumulateStats[service] = (gasUsed, UInt32(num))
        }

        // update lastAccAt
        for (service, _) in accumulateStats {
            if var account = try await get(serviceAccount: service) {
                account.lastAccAt = timeslot
                set(serviceAccount: service, account: account)
            }
        }

        // commitments (accumulation output log)
        let commitmentsSorted = accumulateOutput.commitments.sorted {
            if $0.serviceIndex == $1.serviceIndex {
                return $0.hash < $1.hash
            }
            return $0.serviceIndex < $1.serviceIndex
        }
        logger.debug("accumulation commitments sorted: \(commitmentsSorted)")

        // get accumulate root
        let nodes = try commitmentsSorted.map { try JamEncoder.encode($0.serviceIndex) + JamEncoder.encode($0.hash) }

        logger.debug("accumulation commitments encoded: \(nodes.map { $0.toHexString() })")

        let root = Merklization.binaryMerklize(nodes, hasher: Keccak.self)

        logger.debug("accumulation root: \(root)")

        return (root, commitmentsSorted, accumulateStats)
    }
}
