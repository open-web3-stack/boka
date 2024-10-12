import Foundation
import Utils

public struct AccumulateArguments: Codable {
    public var result: WorkResult
    public var paylaodHash: Data32
    public var packageHash: Data32
    public var authorizationOutput: Data

    public init(result: WorkResult, paylaodHash: Data32, packageHash: Data32, authorizationOutput: Data) {
        self.result = result
        self.paylaodHash = paylaodHash
        self.packageHash = packageHash
        self.authorizationOutput = authorizationOutput
    }
}

public struct DeferredTransfers: Codable {
    // s
    public var sender: ServiceIndex
    // d
    public var destination: ServiceIndex
    // a
    public var amount: Balance
    // m
    public var memo: Data128
    // g
    public var gasLimit: Gas

    public init(sender: ServiceIndex, destination: ServiceIndex, amount: Balance, memo: Data128, gasLimit: Gas) {
        self.sender = sender
        self.destination = destination
        self.amount = amount
        self.memo = memo
        self.gasLimit = gasLimit
    }
}

public struct AccumlateResultContext {
    // s: updated current account
    public var account: ServiceAccount?
    // c
    public var authorizationQueue: ConfigFixedSizeArray<
        ConfigFixedSizeArray<
            Data32,
            ProtocolConfig.MaxAuthorizationsQueueItems
        >,
        ProtocolConfig.TotalNumberOfCores
    >
    // v
    public var validatorQueue: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    >
    // i
    public var serviceIndex: ServiceIndex
    // t
    public var transfers: [DeferredTransfers]
    // n
    public var newAccounts: [ServiceIndex: ServiceAccount]
    // p
    public var privilegedServices: PrivilegedServices

    public init(
        account: ServiceAccount?,
        authorizationQueue: ConfigFixedSizeArray<
            ConfigFixedSizeArray<
                Data32,
                ProtocolConfig.MaxAuthorizationsQueueItems
            >,
            ProtocolConfig.TotalNumberOfCores
        >,
        validatorQueue: ConfigFixedSizeArray<
            ValidatorKey, ProtocolConfig.TotalNumberOfValidators
        >,
        serviceIndex: ServiceIndex,
        transfers: [DeferredTransfers],
        newAccounts: [ServiceIndex: ServiceAccount],
        privilegedServices: PrivilegedServices
    ) {
        self.account = account
        self.authorizationQueue = authorizationQueue
        self.validatorQueue = validatorQueue
        self.serviceIndex = serviceIndex
        self.transfers = transfers
        self.newAccounts = newAccounts
        self.privilegedServices = privilegedServices
    }
}

public protocol AccumulateFunction {
    func invoke(
        config: ProtocolConfigRef,
        serviceIndex: ServiceIndex,
        code: Data,
        serviceAccounts: [ServiceIndex: ServiceAccount],
        gas: Gas,
        arguments: [AccumulateArguments],
        // other inputs needed (not directly in GP's Accumulation function signature)
        validatorQueue: ConfigFixedSizeArray<
            ValidatorKey, ProtocolConfig.TotalNumberOfValidators
        >,
        authorizationQueue: ConfigFixedSizeArray<
            ConfigFixedSizeArray<
                Data32,
                ProtocolConfig.MaxAuthorizationsQueueItems
            >,
            ProtocolConfig.TotalNumberOfCores
        >,
        privilegedServices: PrivilegedServices,
        initialIndex: ServiceIndex,
        timeslot: TimeslotIndex
    ) throws -> (ctx: AccumlateResultContext, result: Data32?)
}
