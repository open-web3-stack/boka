import Foundation
import Utils

private enum StateLayerValue: Sendable {
    case value(Codable & Sendable)
    case deleted

    init(_ value: (Codable & Sendable)?) {
        if let value {
            self = .value(value)
        } else {
            self = .deleted
        }
    }

    func value<T>() -> T? {
        if case let .value(value) = self {
            return value as? T
        }
        return nil
    }

    var codableValue: (Codable & Sendable)? {
        if case let .value(value) = self {
            return value
        }
        return nil
    }

    var isDeleted: Bool {
        if case .deleted = self {
            return true
        }
        return false
    }
}

private struct StateLayerKeyValueSequence: Sequence {
    typealias Element = (key: Data31, value: (Codable & Sendable)?)

    let changes: [Data31: StateLayerValue]

    func makeIterator() -> Iterator {
        Iterator(iterator: changes.makeIterator())
    }

    struct Iterator: IteratorProtocol {
        private var iterator: Dictionary<Data31, StateLayerValue>.Iterator

        fileprivate init(iterator: Dictionary<Data31, StateLayerValue>.Iterator) {
            self.iterator = iterator
        }

        mutating func next() -> Element? {
            guard let item = iterator.next() else {
                return nil
            }
            return (key: item.key, value: item.value.codableValue)
        }
    }
}

private enum FixedStateLayerKeys {
    static let coreAuthorizationPool = StateKeys.CoreAuthorizationPoolKey().encode()
    static let authorizationQueue = StateKeys.AuthorizationQueueKey().encode()
    static let recentHistory = StateKeys.RecentHistoryKey().encode()
    static let safroleState = StateKeys.SafroleStateKey().encode()
    static let judgements = StateKeys.JudgementsKey().encode()
    static let entropyPool = StateKeys.EntropyPoolKey().encode()
    static let validatorQueue = StateKeys.ValidatorQueueKey().encode()
    static let currentValidators = StateKeys.CurrentValidatorsKey().encode()
    static let previousValidators = StateKeys.PreviousValidatorsKey().encode()
    static let reports = StateKeys.ReportsKey().encode()
    static let timeslot = StateKeys.TimeslotKey().encode()
    static let privilegedServices = StateKeys.PrivilegedServicesKey().encode()
    static let activityStatistics = StateKeys.ActivityStatisticsKey().encode()
    static let accumulationQueue = StateKeys.AccumulationQueueKey().encode()
    static let accumulationHistory = StateKeys.AccumulationHistoryKey().encode()
    static let lastAccumulationOutputs = StateKeys.LastAccumulationOutputsKey().encode()
}

public struct StateLayer: Sendable {
    private var changes: [Data31: StateLayerValue] = [:]

    public init(backend: StateBackend) async throws {
        let results = try await backend.batchRead(StateKeys.prefetchKeys)

        for (key, value) in results {
            changes[key.encode()] = try .init(value.unwrap())
        }
    }

    public init(changes: [(key: any StateKey, value: Codable & Sendable)]) {
        for (key, value) in changes {
            self.changes[key.encode()] = .value(value)
        }
    }

    public init(copying other: StateLayer) {
        changes = other.changes
    }

    // α: The core αuthorizations pool.
    public var coreAuthorizationPool: StateKeys.CoreAuthorizationPoolKey.Value {
        get {
            changes[FixedStateLayerKeys.coreAuthorizationPool]!.value()!
        }
        set {
            changes[FixedStateLayerKeys.coreAuthorizationPool] = .init(newValue)
        }
    }

    // φ: The authorization queue.
    public var authorizationQueue: StateKeys.AuthorizationQueueKey.Value {
        get {
            changes[FixedStateLayerKeys.authorizationQueue]!.value()!
        }
        set {
            changes[FixedStateLayerKeys.authorizationQueue] = .init(newValue)
        }
    }

    // β: Information on the most recent βlocks.
    public var recentHistory: StateKeys.RecentHistoryKey.Value {
        get {
            changes[FixedStateLayerKeys.recentHistory]!.value()!
        }
        set {
            changes[FixedStateLayerKeys.recentHistory] = .init(newValue)
        }
    }

    // γ: State concerning Safrole.
    public var safroleState: StateKeys.SafroleStateKey.Value {
        get {
            changes[FixedStateLayerKeys.safroleState]!.value()!
        }
        set {
            changes[FixedStateLayerKeys.safroleState] = .init(newValue)
        }
    }

    // ψ: past judgements
    public var judgements: StateKeys.JudgementsKey.Value {
        get {
            changes[FixedStateLayerKeys.judgements]!.value()!
        }
        set {
            changes[FixedStateLayerKeys.judgements] = .init(newValue)
        }
    }

    // η: The eηtropy accumulator and epochal raηdomness.
    public var entropyPool: StateKeys.EntropyPoolKey.Value {
        get {
            changes[FixedStateLayerKeys.entropyPool]!.value()!
        }
        set {
            changes[FixedStateLayerKeys.entropyPool] = .init(newValue)
        }
    }

    // ι: The validator keys and metadata to be drawn from next.
    public var validatorQueue: StateKeys.ValidatorQueueKey.Value {
        get {
            changes[FixedStateLayerKeys.validatorQueue]!.value()!
        }
        set {
            changes[FixedStateLayerKeys.validatorQueue] = .init(newValue)
        }
    }

    // κ: The validator κeys and metadata currently active.
    public var currentValidators: StateKeys.CurrentValidatorsKey.Value {
        get {
            changes[FixedStateLayerKeys.currentValidators]!.value()!
        }
        set {
            changes[FixedStateLayerKeys.currentValidators] = .init(newValue)
        }
    }

    // λ: The validator keys and metadata which were active in the prior epoch.
    public var previousValidators: StateKeys.PreviousValidatorsKey.Value {
        get {
            changes[FixedStateLayerKeys.previousValidators]!.value()!
        }
        set {
            changes[FixedStateLayerKeys.previousValidators] = .init(newValue)
        }
    }

    // ρ: The ρending reports, per core, which are being made available prior to accumulation.
    public var reports: StateKeys.ReportsKey.Value {
        get {
            changes[FixedStateLayerKeys.reports]!.value()!
        }
        set {
            changes[FixedStateLayerKeys.reports] = .init(newValue)
        }
    }

    // τ: The most recent block’s τimeslot.
    public var timeslot: StateKeys.TimeslotKey.Value {
        get {
            changes[FixedStateLayerKeys.timeslot]!.value()!
        }
        set {
            changes[FixedStateLayerKeys.timeslot] = .init(newValue)
        }
    }

    // χ: The privileged service indices.
    public var privilegedServices: StateKeys.PrivilegedServicesKey.Value {
        get {
            changes[FixedStateLayerKeys.privilegedServices]!.value()!
        }
        set {
            changes[FixedStateLayerKeys.privilegedServices] = .init(newValue)
        }
    }

    // π: The activity statistics for the validators.
    public var activityStatistics: StateKeys.ActivityStatisticsKey.Value {
        get {
            changes[FixedStateLayerKeys.activityStatistics]!.value()!
        }
        set {
            changes[FixedStateLayerKeys.activityStatistics] = .init(newValue)
        }
    }

    // ϑ: The accumulation queue.
    public var accumulationQueue: StateKeys.AccumulationQueueKey.Value {
        get {
            changes[FixedStateLayerKeys.accumulationQueue]!.value()!
        }
        set {
            changes[FixedStateLayerKeys.accumulationQueue] = .init(newValue)
        }
    }

    // ξ: The accumulation history.
    public var accumulationHistory: StateKeys.AccumulationHistoryKey.Value {
        get {
            changes[FixedStateLayerKeys.accumulationHistory]!.value()!
        }
        set {
            changes[FixedStateLayerKeys.accumulationHistory] = .init(newValue)
        }
    }

    // θ: The most recent Accumulation outputs
    public var lastAccumulationOutputs: StateKeys.LastAccumulationOutputsKey.Value {
        get {
            changes[FixedStateLayerKeys.lastAccumulationOutputs]!.value()!
        }
        set {
            changes[FixedStateLayerKeys.lastAccumulationOutputs] = .init(newValue)
        }
    }

    // δ: The (prior) state of the service accounts.
    public subscript(serviceAccount index: ServiceIndex) -> StateKeys.ServiceAccountKey.Value? {
        get {
            changes[StateKeys.ServiceAccountKey(index: index).encode()]?.value()
        }
        set {
            changes[StateKeys.ServiceAccountKey(index: index).encode()] = .init(newValue)
        }
    }

    /// s
    public subscript(serviceAccount index: ServiceIndex, storageKey key: Data) -> StateKeys.ServiceAccountStorageKey.Value? {
        get {
            changes[StateKeys.ServiceAccountStorageKey(index: index, key: key).encode()]?.value()
        }
        set {
            changes[StateKeys.ServiceAccountStorageKey(index: index, key: key).encode()] = .init(newValue)
        }
    }

    /// p
    public subscript(
        serviceAccount index: ServiceIndex, preimageHash hash: Data32,
    ) -> StateKeys.ServiceAccountPreimagesKey.Value? {
        get {
            changes[StateKeys.ServiceAccountPreimagesKey(index: index, hash: hash).encode()]?.value()
        }
        set {
            changes[StateKeys.ServiceAccountPreimagesKey(index: index, hash: hash).encode()] = .init(newValue)
        }
    }

    /// l
    public subscript(
        serviceAccount index: ServiceIndex, preimageHash hash: Data32, length length: UInt32,
    ) -> StateKeys.ServiceAccountPreimageInfoKey.Value? {
        get {
            changes[
                StateKeys.ServiceAccountPreimageInfoKey(
                    index: index, hash: hash, length: length,
                ).encode(),
            ]?.value()
        }
        set {
            changes[
                StateKeys.ServiceAccountPreimageInfoKey(
                    index: index, hash: hash, length: length,
                ).encode(),
            ] = .init(newValue)
        }
    }
}

extension StateLayer {
    public func toKV() -> some Sequence<(key: Data31, value: (Codable & Sendable)?)> {
        StateLayerKeyValueSequence(changes: changes)
    }
}

extension StateLayer {
    public func read<Key: StateKey>(_ key: Key) -> Key.Value? {
        changes[key.encode()] as? Key.Value
    }

    public mutating func write<Key: StateKey>(_ key: Key, value: Key.Value?) {
        changes[key.encode()] = .init(value)
    }

    public subscript(key: any StateKey) -> (Codable & Sendable)? {
        get {
            changes[key.encode()]?.value()
        }
        set {
            changes[key.encode()] = .init(newValue)
        }
    }

    public subscript(key: Data31) -> (Codable & Sendable)? {
        get {
            changes[key]?.value()
        }
        set {
            changes[key] = .init(newValue)
        }
    }

    public func isDeleted(serviceAccount index: ServiceIndex) -> Bool {
        changes[StateKeys.ServiceAccountKey(index: index).encode()]?.isDeleted ?? false
    }

    public func isDeleted(serviceAccount index: ServiceIndex, storageKey key: Data) -> Bool {
        changes[StateKeys.ServiceAccountStorageKey(index: index, key: key).encode()]?.isDeleted ?? false
    }

    public func isDeleted(serviceAccount index: ServiceIndex, preimageHash hash: Data32) -> Bool {
        changes[StateKeys.ServiceAccountPreimagesKey(index: index, hash: hash).encode()]?.isDeleted ?? false
    }

    public func isDeleted(serviceAccount index: ServiceIndex, preimageHash hash: Data32, length: UInt32) -> Bool {
        changes[StateKeys.ServiceAccountPreimageInfoKey(index: index, hash: hash, length: length).encode()]?.isDeleted ?? false
    }
}
