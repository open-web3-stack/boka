import Codec
import TracingUtils
import Utils

private let logger = Logger(label: "Accumulation")

public enum AccumulationError: Error {
    case invalidServiceIndex
    case duplicatedServiceIndex
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
}

/// parallelized accumulation function ∆* output
public struct ParallelAccumulationOutput {
    public var gasUsed: Gas
    public var state: AccumulateState
    public var transfers: [DeferredTransfers]
    public var commitments: Set<Commitment>
}

/// single-service accumulation function ∆1 output
public struct SingleAccumulationOutput {
    // o
    public var state: AccumulateState
    // t
    public var transfers: [DeferredTransfers]
    // b
    public var commitment: Data32?
    // u
    public var gasUsed: Gas
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

extension Accumulation {
    /// single-service accumulate function ∆1
    private mutating func singleAccumulate(
        config: ProtocolConfigRef,
        state: AccumulateState,
        workReports: [WorkReport],
        service: ServiceIndex,
        privilegedGas: [ServiceIndex: Gas],
        entropy: Data32,
        timeslot: TimeslotIndex
    ) async throws -> SingleAccumulationOutput {
        var gas = Gas(0)
        var arguments: [AccumulateArguments] = []

        for basicGas in privilegedGas.values {
            gas += basicGas
        }

        for report in workReports {
            for result in report.results where result.serviceIndex == service {
                gas += result.gasRatio
                arguments.append(AccumulateArguments(
                    output: result.output,
                    paylaodHash: result.payloadHash,
                    packageHash: report.packageSpecification.workPackageHash,
                    authorizationOutput: report.authorizationOutput
                ))
            }
        }

        logger.debug("[single] accumulate arguments: \(arguments)")

        let (newState, transfers, commitment, gasUsed) = try await accumulate(
            config: config,
            accounts: &self,
            state: state,
            serviceIndex: service,
            gas: gas,
            arguments: arguments,
            initialIndex: Blake2b256.hash(service.encode(), entropy.data, timeslot.encode()).data.decode(UInt32.self),
            timeslot: timeslot
        )

        logger.debug("[single] accumulate result: gasUsed=\(gasUsed), commitment=\(String(describing: commitment))")

        return SingleAccumulationOutput(
            state: newState,
            transfers: transfers,
            commitment: commitment,
            gasUsed: gasUsed
        )
    }

    /// parallelized accumulate function ∆*
    private mutating func parallelizedAccumulate(
        config: ProtocolConfigRef,
        state: AccumulateState,
        workReports: [WorkReport],
        privilegedGas: [ServiceIndex: Gas],
        entropy: Data32,
        timeslot: TimeslotIndex
    ) async throws -> ParallelAccumulationOutput {
        var services = [ServiceIndex]()
        var gasUsed = Gas(0)
        var transfers: [DeferredTransfers] = []
        var commitments = Set<Commitment>()
        var newServiceAccounts = [ServiceIndex: ServiceAccount]()
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

        for report in workReports {
            for result in report.results {
                services.append(result.serviceIndex)
            }
        }

        for service in privilegedGas.keys {
            services.append(service)
        }

        logger.debug("[parallel] services to accumulate: \(services)")

        for service in services {
            let singleOutput = try await singleAccumulate(
                config: config,
                state: state,
                workReports: workReports,
                service: service,
                privilegedGas: privilegedGas,
                entropy: entropy,
                timeslot: timeslot
            )
            gasUsed += singleOutput.gasUsed

            if let commitment = singleOutput.commitment {
                commitments.insert(Commitment(service: service, hash: commitment))
            }

            for transfer in singleOutput.transfers {
                transfers.append(transfer)
            }

            // new service accounts
            for (service, account) in singleOutput.state.newServiceAccounts {
                guard newServiceAccounts[service] == nil, try await get(serviceAccount: service) == nil else {
                    throw AccumulationError.duplicatedServiceIndex
                }
                newServiceAccounts[service] = account
            }

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
        }

        return ParallelAccumulationOutput(
            gasUsed: gasUsed,
            state: AccumulateState(
                newServiceAccounts: newServiceAccounts,
                validatorQueue: newValidatorQueue ?? validatorQueue,
                authorizationQueue: newAuthorizationQueue ?? authorizationQueue,
                privilegedServices: newPrivilegedServices ?? privilegedServices
            ),
            transfers: transfers,
            commitments: commitments
        )
    }

    /// outer accumulate function ∆+
    private mutating func outerAccumulate(
        config: ProtocolConfigRef,
        state: AccumulateState,
        workReports: [WorkReport],
        privilegedGas: [ServiceIndex: Gas],
        gasLimit: Gas,
        entropy: Data32,
        timeslot: TimeslotIndex
    ) async throws -> AccumulationOutput {
        var i = 0
        var sumGasRequired = Gas(0)

        for report in workReports {
            var canAccumulate = true
            for result in report.results {
                if result.gasRatio + sumGasRequired > gasLimit {
                    canAccumulate = false
                    break
                }
                sumGasRequired += result.gasRatio
            }
            i += canAccumulate ? 1 : 0
        }

        if i == 0 {
            return AccumulationOutput(
                numAccumulated: 0,
                state: state,
                transfers: [],
                commitments: Set()
            )
        } else {
            logger.debug("[outer] can accumulate until index: \(i)")

            let parallelOutput = try await parallelizedAccumulate(
                config: config,
                state: state,
                workReports: Array(workReports[0 ..< i]),
                privilegedGas: privilegedGas,
                entropy: entropy,
                timeslot: timeslot
            )
            let outerOutput = try await outerAccumulate(
                config: config,
                state: parallelOutput.state,
                workReports: Array(workReports[i ..< workReports.count]),
                privilegedGas: [:],
                gasLimit: gasLimit - parallelOutput.gasUsed,
                entropy: entropy,
                timeslot: timeslot
            )
            return AccumulationOutput(
                numAccumulated: i + outerOutput.numAccumulated,
                state: outerOutput.state,
                transfers: parallelOutput.transfers + outerOutput.transfers,
                commitments: parallelOutput.commitments.union(outerOutput.commitments)
            )
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
        entropy: Data32,
        timeslot: TimeslotIndex
    ) async throws -> AccumulationOutput {
        let sumPrevilegedGas = privilegedServices.basicGas.values.reduce(Gas(0)) { $0 + $1.value }
        let minTotalGas = config.value.workReportAccumulationGas * Gas(config.value.totalNumberOfCores) + sumPrevilegedGas
        let gasLimit = max(config.value.totalAccumulationGas, minTotalGas)

        return try await outerAccumulate(
            config: config,
            state: AccumulateState(
                newServiceAccounts: [:],
                validatorQueue: validatorQueue,
                authorizationQueue: authorizationQueue,
                privilegedServices: privilegedServices
            ),
            workReports: workReports,
            privilegedGas: privilegedServices.basicGas,
            gasLimit: gasLimit,
            entropy: entropy,
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
    ) async throws -> Data32 {
        let index = Int(timeslot) %% config.value.epochLength

        logger.debug("available reports (\(availableReports.count)): \(availableReports.map(\.packageSpecification.workPackageHash))")

        var (accumulatableReports, newQueueItems) = getAllAccumulatableReports(
            availableReports: availableReports,
            index: index
        )

        logger.debug("accumulatable reports: \(accumulatableReports.map(\.packageSpecification.workPackageHash))")

        let accumulateOutput = try await execution(
            config: config,
            workReports: accumulatableReports,
            entropy: entropy,
            timeslot: timeslot
        )

        authorizationQueue = accumulateOutput.state.authorizationQueue
        validatorQueue = accumulateOutput.state.validatorQueue
        privilegedServices = accumulateOutput.state.privilegedServices

        // add new service accounts
        for (service, account) in accumulateOutput.state.newServiceAccounts {
            set(serviceAccount: service, account: account.toDetails())
            for (hash, value) in account.storage {
                set(serviceAccount: service, storageKey: hash, value: value)
            }
            for (hash, value) in account.preimages {
                set(serviceAccount: service, preimageHash: hash, value: value)
            }
            for (hashLength, value) in account.preimageInfos {
                set(serviceAccount: service, preimageHash: hashLength.hash, length: hashLength.length, value: value)
            }
        }

        // transfers
        var transferGroups = [ServiceIndex: [DeferredTransfers]]()
        for transfer in accumulateOutput.transfers {
            transferGroups[transfer.destination, default: []].append(transfer)
        }
        for (service, transfers) in transferGroups {
            try await onTransfer(
                config: config,
                serviceIndex: service,
                serviceAccounts: &self,
                timeslot: timeslot,
                transfers: transfers
            )
        }

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

        // accumulate root
        let nodes = try accumulateOutput.commitments.map { try JamEncoder.encode($0.serviceIndex) + JamEncoder.encode($0.hash) }
        let root = Merklization.binaryMerklize(nodes, hasher: Keccak.self)

        logger.debug("accumulation root: \(root.toHexString())")

        return root
    }
}
