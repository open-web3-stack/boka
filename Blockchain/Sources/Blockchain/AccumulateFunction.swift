import Foundation
import Utils

public struct AccumulateArguments {
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

public struct DeferredTransfers {
    // s
    public var sender: ServiceIndex
    // d
    public var destination: ServiceIndex
    // a
    public var amount: Balance
    // m
    public var memo: Data64
    // g
    public var gasLimit: Gas

    public init(sender: ServiceIndex, destination: ServiceIndex, amount: Balance, memo: Data64, gasLimit: Gas) {
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
}

public protocol AccumulateFunction {
    func invoke(
        config: ProtocolConfigRef,
        service: ServiceIndex,
        code: Data,
        serviceAccounts: [ServiceIndex: ServiceAccount],
        gas: Gas,
        arguments: [AccumulateArguments]
    ) throws -> (ctx: AccumlateResultContext, result: Data32?)
}
