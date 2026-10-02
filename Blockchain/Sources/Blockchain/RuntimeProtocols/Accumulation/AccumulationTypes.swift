import Codec
import Utils

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

/// accumulation output pairing
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
    /// e
    public var state: AccumulateState
    /// t
    public var transfers: [DeferredTransfers]
    /// y
    public var commitment: Data32?
    /// u
    public var gasUsed: Gas
    /// p
    public var provide: Set<ServicePreimagePair>
}

public typealias AccumulationStats = [ServiceIndex: (Gas, UInt32)]
