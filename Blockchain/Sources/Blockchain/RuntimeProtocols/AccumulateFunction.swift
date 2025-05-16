import Foundation
import Utils

// wrangled operand tuple
public struct AccumulateArguments: Codable {
    /// h
    public var packageHash: Data32
    /// e
    public var segmentRoot: Data32
    /// a
    public var authorizerHash: Data32
    /// o
    public var authorizerTrace: Data
    /// y
    public var payloadHash: Data32
    /// d
    public var workResult: WorkResult
    /// g
    public var gasRatio: Gas
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
    /// d (all service accounts)
    public var accounts: ServiceAccountsMutRef
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

    public func copy() -> AccumulateState {
        AccumulateState(
            accounts: ServiceAccountsMutRef(accounts.value),
            validatorQueue: validatorQueue,
            authorizationQueue: authorizationQueue,
            privilegedServices: privilegedServices
        )
    }
}

/// X
public class AccumlateResultContext {
    /// s: the accumulating service account index
    public var serviceIndex: ServiceIndex
    /// u
    public var state: AccumulateState
    /// i
    public var nextAccountIndex: ServiceIndex
    /// t: deferred transfers
    public var transfers: [DeferredTransfers]
    /// y
    public var yield: Data32?
    /// p: preimages to be provided
    public var providePreimages: Set<ServicePreimagePair>

    public var accountChanges: AccountChanges

    public init(
        serviceIndex: ServiceIndex,
        state: AccumulateState,
        nextAccountIndex: ServiceIndex
    ) {
        self.serviceIndex = serviceIndex
        self.state = state
        self.nextAccountIndex = nextAccountIndex
        transfers = []
        yield = nil
        providePreimages = []
        accountChanges = AccountChanges()
    }
}
