import Codec
import Foundation
import Utils

public struct OperandTuple: Codable, Sendable {
    /// p
    public var packageHash: Data32
    /// e
    public var segmentRoot: Data32
    /// a
    public var authorizerHash: Data32
    /// y
    public var payloadHash: Data32
    /// g
    @CodingAs<Compact<Gas>> public var gasLimit: Gas
    /// l
    public var workResult: WorkResult
    /// t
    public var authorizerTrace: Data
}

public struct DeferredTransfers: Codable, Sendable {
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

public struct AccumulationInput: Sendable, Codable {
    public enum InputType: Sendable, Equatable {
        case operandTuple
        case deferredTransfers
    }

    public var inputType: InputType
    public var operandTuple: OperandTuple?
    public var deferredTransfers: DeferredTransfers?

    public init(operandTuple: OperandTuple) {
        inputType = .operandTuple
        self.operandTuple = operandTuple
    }

    public init(deferredTransfers: DeferredTransfers) {
        inputType = .deferredTransfers
        self.deferredTransfers = deferredTransfers
    }

    // Encodable
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        switch inputType {
        case .operandTuple:
            try container.encode(UInt(0))
            try container.encode(operandTuple.unwrap())
        case .deferredTransfers:
            try container.encode(UInt(1))
            try container.encode(deferredTransfers.unwrap())
        }
    }

    // Decodable
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let variant = try container.decode(UInt.self)
        switch variant {
        case 0:
            let operandTuple = try container.decode(OperandTuple.self)
            self.init(operandTuple: operandTuple)
        case 1:
            let deferredTransfers = try container.decode(DeferredTransfers.self)
            self.init(deferredTransfers: deferredTransfers)
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid AccumulationInput variant: \(variant)"
                )
            )
        }
    }
}

/// Characterization (i.e. values capable of representing) of state components
/// which are both needed and mutable by the accumulation process.
public struct AccumulateState: Sendable {
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
    // m
    public var manager: ServiceIndex
    // a
    public var assigners: ConfigFixedSizeArray<ServiceIndex, ProtocolConfig.TotalNumberOfCores>
    // v
    public var delegator: ServiceIndex
    // r
    public var registrar: ServiceIndex
    // z
    public var alwaysAcc: [ServiceIndex: Gas]

    public var entropy: Data32 // eta'_0

    public func copy() -> AccumulateState {
        AccumulateState(
            accounts: ServiceAccountsMutRef(copying: accounts),
            validatorQueue: validatorQueue,
            authorizationQueue: authorizationQueue,
            manager: manager,
            assigners: assigners,
            delegator: delegator,
            registrar: registrar,
            alwaysAcc: alwaysAcc,
            entropy: entropy
        )
    }
}

public class AccumulateResultContext {
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
    /// p
    public var provide: Set<ServicePreimagePair>

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
        provide = []
        accountChanges = AccountChanges()
    }
}
