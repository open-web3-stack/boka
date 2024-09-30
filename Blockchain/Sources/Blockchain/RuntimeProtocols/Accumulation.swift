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
    public var serviceAccounts: [ServiceIndex: ServiceAccount]
}

public protocol Accumulation {
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
    var serviceAccounts: [ServiceIndex: ServiceAccount] { get }
    var accumlateFunction: AccumulateFunction { get }
    var onTransferFunction: OnTransferFunction { get }
}

extension Accumulation {
    public func update(config: ProtocolConfigRef, block: BlockRef, workReports: [WorkReport]) throws -> AccumulationOutput {
        var servicesGasRatio: [ServiceIndex: Gas] = [:]
        var servicesGas: [ServiceIndex: Gas] = [:]

        // privileged gas
        for (service, gas) in privilegedServices.basicGas {
            servicesGas[service] = gas
        }

        let totalGasRatio = workReports.flatMap(\.results).reduce(0) { $0 + $1.gasRatio }
        let totalMinimalGas = try workReports.flatMap(\.results)
            .reduce(0) { try $0 + serviceAccounts[$1.serviceIndex].unwrap(orError: AccumulationError.invalidServiceIndex).minAccumlateGas }
        for report in workReports {
            for result in report.results {
                servicesGasRatio[result.serviceIndex, default: 0] += result.gasRatio
                servicesGas[result.serviceIndex, default: 0] += try serviceAccounts[result.serviceIndex]
                    .unwrap(orError: AccumulationError.invalidServiceIndex).minAccumlateGas
            }
        }
        let remainingGas = config.value.coreAccumulationGas - totalMinimalGas

        for (service, gas) in servicesGas {
            servicesGas[service] = gas + servicesGasRatio[service, default: 0] * remainingGas / totalGasRatio
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

        var newServiceAccounts = serviceAccounts

        var transferReceivers = [ServiceIndex: [DeferredTransfers]]()

        for (service, arguments) in serviceArguments {
            guard let gas = servicesGas[service] else {
                assertionFailure("unreachable: service not found")
                throw AccumulationError.invalidServiceIndex
            }
            let acc = try serviceAccounts[service].unwrap(orError: AccumulationError.invalidServiceIndex)
            guard let code = acc.preimages[acc.codeHash] else {
                continue
            }
            let (ctx, commitment) = try accumlateFunction.invoke(
                config: config,
                serviceIndex: service,
                code: code,
                serviceAccounts: serviceAccounts,
                gas: gas,
                arguments: arguments,
                validatorQueue: validatorQueue,
                authorizationQueue: authorizationQueue,
                privilegedServices: privilegedServices,
                initialIndex: Blake2b256.hash(service.encode(), entropyPool.t0.data, block.header.timeslot.encode())
                    .data.decode(UInt32.self),
                timeslot: block.header.timeslot
            )
            if let commitment {
                commitments.append((service, commitment))
            }

            for (service, account) in ctx.newAccounts {
                guard newServiceAccounts[service] == nil else {
                    throw AccumulationError.duplicatedServiceIndex
                }
                newServiceAccounts[service] = account
            }

            newServiceAccounts[service] = ctx.account

            switch service {
            case privilegedServices.empower:
                newPrivilegedServices = ctx.privilegedServices
            case privilegedServices.assign:
                newAuthorizationQueue = ctx.authorizationQueue
            case privilegedServices.designate:
                newValidatorQueue = ctx.validatorQueue
            default:
                break
            }

            for transfer in ctx.transfers {
                transferReceivers[transfer.sender, default: []].append(transfer)
            }
        }

        for (service, transfers) in transferReceivers {
            let acc = try serviceAccounts[service].unwrap(orError: AccumulationError.invalidServiceIndex)
            guard let code = acc.preimages[acc.codeHash] else {
                continue
            }
            newServiceAccounts[service] = try onTransferFunction.invoke(
                config: config,
                service: service,
                code: code,
                serviceAccounts: newServiceAccounts,
                transfers: transfers
            )
        }

        return .init(
            commitments: commitments,
            // those cannot be nil because priviledge services are always called
            privilegedServices: newPrivilegedServices!,
            validatorQueue: newValidatorQueue!,
            authorizationQueue: newAuthorizationQueue!,
            serviceAccounts: newServiceAccounts
        )
    }
}
