import Utils

public enum AccumulationError: Error {
    case invalidServiceIndex
    case duplicatedServiceIndex
}

public struct AccumulationOutput {
    public var commitments: [(ServiceIndex, Data32)]
    public var privilegedServices: PrivilegedServices
    public var validatorQueue: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    >
    public var authorizationQueue: ConfigFixedSizeArray<
        ConfigFixedSizeArray<
            Data32,
            ProtocolConfig.MaxAuthorizationsQueueItems
        >,
        ProtocolConfig.TotalNumberOfCores
    >
    public var newServiceAccounts: [ServiceIndex: ServiceAccount]
}

public protocol Accumulation: ServiceAccounts {
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
    var entropyPool: EntropyPool { get }
    var accumlateFunction: AccumulateFunction { get }
    var onTransferFunction: OnTransferFunction { get }
}

extension Accumulation {
    public mutating func update(config: ProtocolConfigRef, block: BlockRef, workReports: [WorkReport]) async throws -> AccumulationOutput {
        var servicesGasRatio: [ServiceIndex: Gas] = [:]
        var servicesGas: [ServiceIndex: Gas] = [:]

        // privileged gas
        for (service, gas) in privilegedServices.basicGas {
            servicesGas[service] = gas
        }

        let totalGasRatio = workReports.flatMap(\.results).reduce(Gas(0)) { $0 + $1.gasRatio }
        var totalMinimalGas = Gas(0)
        for report in workReports {
            for result in report.results {
                servicesGasRatio[result.serviceIndex, default: Gas(0)] += result.gasRatio
                let acc = try await get(serviceAccount: result.serviceIndex).unwrap(orError: AccumulationError.invalidServiceIndex)
                totalMinimalGas += acc.minAccumlateGas
                servicesGas[result.serviceIndex, default: Gas(0)] += acc.minAccumlateGas
            }
        }
        let remainingGas = config.value.coreAccumulationGas - totalMinimalGas

        for (service, gas) in servicesGas {
            servicesGas[service] = gas + servicesGasRatio[service, default: Gas(0)] * remainingGas / totalGasRatio
        }

        var serviceArguments: [ServiceIndex: [AccumulateArguments]] = [:]

        // ensure privileged services will be called
        for service in privilegedServices.basicGas.keys {
            serviceArguments[service] = []
        }

        for report in workReports {
            for result in report.results {
                serviceArguments[result.serviceIndex, default: []].append(AccumulateArguments(
                    result: result,
                    paylaodHash: result.payloadHash,
                    packageHash: report.packageSpecification.workPackageHash,
                    authorizationOutput: report.authorizationOutput
                ))
            }
        }

        var commitments = [(ServiceIndex, Data32)]()
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

        var newServiceAccounts = [ServiceIndex: ServiceAccount]()
        var transferReceivers = [ServiceIndex: [DeferredTransfers]]()

        for (service, arguments) in serviceArguments {
            guard let gas = servicesGas[service] else {
                assertionFailure("unreachable: service not found")
                throw AccumulationError.invalidServiceIndex
            }
            let (newState, transfers, commitment, _) = try await accumlateFunction.invoke(
                config: config,
                accounts: &self,
                state: AccumulateState(
                    serviceAccounts: [:],
                    validatorQueue: validatorQueue,
                    authorizationQueue: authorizationQueue,
                    privilegedServices: privilegedServices
                ),
                serviceIndex: service,
                gas: gas,
                arguments: arguments,
                initialIndex: Blake2b256.hash(service.encode(), entropyPool.t0.data, block.header.timeslot.encode())
                    .data.decode(UInt32.self),
                timeslot: block.header.timeslot
            )
            if let commitment {
                commitments.append((service, commitment))
            }

            for (service, account) in newState.serviceAccounts {
                guard newServiceAccounts[service] == nil else {
                    throw AccumulationError.duplicatedServiceIndex
                }
                newServiceAccounts[service] = account
            }

            switch service {
            case privilegedServices.empower:
                newPrivilegedServices = newState.privilegedServices
            case privilegedServices.assign:
                newAuthorizationQueue = newState.authorizationQueue
            case privilegedServices.designate:
                newValidatorQueue = newState.validatorQueue
            default:
                break
            }

            for transfer in transfers {
                transferReceivers[transfer.sender, default: []].append(transfer)
            }
        }

        for (service, transfers) in transferReceivers {
            let acc = try await get(serviceAccount: service).unwrap(orError: AccumulationError.invalidServiceIndex)
            let code = try await get(serviceAccount: service, preimageHash: acc.codeHash)
            guard let code else {
                continue
            }
            try await onTransferFunction.invoke(
                config: config,
                service: service,
                code: code,
                serviceAccounts: &self,
                transfers: transfers
            )
        }

        return .init(
            commitments: commitments,
            privilegedServices: newPrivilegedServices ?? privilegedServices,
            validatorQueue: newValidatorQueue ?? validatorQueue,
            authorizationQueue: newAuthorizationQueue ?? authorizationQueue,
            newServiceAccounts: newServiceAccounts
        )
    }
}
