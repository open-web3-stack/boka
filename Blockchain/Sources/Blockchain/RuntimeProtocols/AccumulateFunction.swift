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

/// U: a characterization (i.e. values capable of representing) of state components
///    which are both needed and mutable by the accumulation process.
public struct AccumulateState {
    /// d
    public var serviceAccounts: [ServiceIndex: ServiceAccount]
    /// i
    public var validatorQueue: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    >
    /// q
    public var authorizationQueue: ConfigFixedSizeArray<
        ConfigFixedSizeArray<
            Data32,
            ProtocolConfig.MaxAuthorizationsQueueItems
        >,
        ProtocolConfig.TotalNumberOfCores
    >
    /// x
    public var privilegedServices: PrivilegedServices
}

/// X
public struct AccumlateResultContext {
    /// d
    public var serviceAccounts: ServiceAccounts
    /// s: the accumulating service account index
    public var serviceIndex: ServiceIndex
    /// u
    public var accumulateState: AccumulateState
    /// i
    public var nextAccountIndex: ServiceIndex
    /// t: deferred transfers
    public var transfers: [DeferredTransfers]
}

public protocol AccumulateFunction {
    func invoke(
        config: ProtocolConfigRef,
        // prior accounts
        accounts: inout some ServiceAccounts,
        // u
        state: AccumulateState,
        // s
        serviceIndex: ServiceIndex,
        // g
        gas: Gas,
        // o
        arguments: [AccumulateArguments],
        initialIndex: ServiceIndex,
        timeslot: TimeslotIndex
    ) async throws -> (state: AccumulateState, transfers: [DeferredTransfers], result: Data32?, gas: Gas)
}
