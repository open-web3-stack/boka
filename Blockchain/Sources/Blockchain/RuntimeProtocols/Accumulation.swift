import Codec
import Utils

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
    var privilegedServices: PrivilegedServices { get }
    var validatorQueue: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    > { get }
    var authorizationQueue: ConfigFixedSizeArray<
        ConfigFixedSizeArray<
            Data32,
            ProtocolConfig.MaxAuthorizationsQueueItems
        >,
        ProtocolConfig.TotalNumberOfCores
    > { get }
    var accumlateFunction: AccumulateFunction { get }
    var onTransferFunction: OnTransferFunction { get }
    var accumulationQueue: StateKeys.AccumulationQueueKey.Value { get }
    var accumulationHistory: StateKeys.AccumulationHistoryKey.Value { get }
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
                    result: result,
                    paylaodHash: result.payloadHash,
                    packageHash: report.packageSpecification.workPackageHash,
                    authorizationOutput: report.authorizationOutput
                ))
            }
        }

        let (newState, transfers, commitment, gasUsed) = try await accumlateFunction.invoke(
            config: config,
            accounts: &self,
            state: state,
            serviceIndex: service,
            gas: gas,
            arguments: arguments,
            initialIndex: Blake2b256.hash(service.encode(), entropy.data, timeslot.encode()).data.decode(UInt32.self),
            timeslot: timeslot
        )

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
        var services = Set<ServiceIndex>()
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
                services.insert(result.serviceIndex)
            }
        }

        for service in privilegedGas.keys {
            services.insert(service)
        }

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
            for result in report.results {
                if result.gasRatio + sumGasRequired > gasLimit {
                    break
                }
                sumGasRequired += result.gasRatio
                i += 1
            }
        }

        if i == 0 {
            return AccumulationOutput(
                numAccumulated: 0,
                state: state,
                transfers: [],
                commitments: Set()
            )
        } else {
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

    // E: edit the accumulation queue, remove the dependencies of the items that are already accumulated
    public func editAccumulatedItems(items: inout [AccumulationQueueItem], accumulatedPackages: Set<Data32>) {
        for index in items.indices
            where !accumulatedPackages.contains(items[index].workReport.packageSpecification.workPackageHash)
        {
            items[index].dependencies.subtract(accumulatedPackages)
        }
    }

    // Q: find the reports that have no dependencies
    private func findNoDepsReports(items: inout [AccumulationQueueItem]) -> [WorkReport] {
        let noDepsReports = items.filter(\.dependencies.isEmpty).map(\.workReport)
        if noDepsReports.isEmpty {
            return []
        } else {
            editAccumulatedItems(items: &items, accumulatedPackages: Set(noDepsReports.map(\.packageSpecification.workPackageHash)))
            return noDepsReports + findNoDepsReports(items: &items)
        }
    }

    // newly available work-reports, W, are partitioned into two sequences based on the condition of having zero prerequisite work-reports
    public func partitionWorkReports(
        availableReports: [WorkReport],
        history: StateKeys.AccumulationHistoryKey.Value
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

        editAccumulatedItems(
            items: &newQueueItems,
            accumulatedPackages: Set(history.array.reduce(into: Set<Data32>()) { $0.formUnion($1.array) })
        )

        return (zeroPrereqReports, newQueueItems)
    }

    public func getAccumulatableReports(
        index: Int, availableReports: [WorkReport],
        history: StateKeys.AccumulationHistoryKey.Value
    ) -> (accumulatableReports: [WorkReport], newQueueItems: [AccumulationQueueItem]) {
        let (zeroPrereqReports, newQueueItems) = partitionWorkReports(availableReports: availableReports, history: history)

        let rightQueueItems = accumulationQueue.array[index...]
        let leftQueueItems = accumulationQueue.array[0 ..< index]
        var allQueueItems = rightQueueItems.flatMap(\.self) + leftQueueItems.flatMap(\.self) + newQueueItems

        editAccumulatedItems(items: &allQueueItems, accumulatedPackages: Set(zeroPrereqReports.map(\.packageSpecification.workPackageHash)))

        return (zeroPrereqReports + findNoDepsReports(items: &allQueueItems), newQueueItems)
    }

    public mutating func update(
        config: ProtocolConfigRef,
        workReports: [WorkReport],
        entropy: Data32,
        timeslot: TimeslotIndex
    ) async throws -> (numAccumulated: Int, state: AccumulateState, commitments: Set<Commitment>) {
        let sumPrevilegedGas = privilegedServices.basicGas.values.reduce(Gas(0)) { $0 + $1.value }
        let minTotalGas = config.value.workReportAccumulationGas * Gas(config.value.totalNumberOfCores) + sumPrevilegedGas
        let gasLimit = max(config.value.totalAccumulationGas, minTotalGas)

        let res = try await outerAccumulate(
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

        var transferGroups = [ServiceIndex: [DeferredTransfers]]()

        for transfer in res.transfers {
            transferGroups[transfer.destination, default: []].append(transfer)
        }

        for (service, transfers) in transferGroups {
            try await onTransferFunction.invoke(
                config: config,
                service: service,
                serviceAccounts: &self,
                timeslot: timeslot,
                transfers: transfers
            )
        }

        return (res.numAccumulated, res.state, res.commitments)
    }
}
