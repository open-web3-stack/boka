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
}

// @unchecked because AnyHashable is not Sendable
public struct StateLayer: @unchecked Sendable {
    private var changes: [AnyHashable: StateLayerValue] = [:]

    public init(backend: StateBackend) async throws {
        let results = try await backend.batchRead(StateKeys.prefetchKeys)

        for (key, value) in results {
            changes[AnyHashable(key)] = try .init(value.unwrap())
        }
    }

    public init(changes: [(key: any StateKey, value: Codable & Sendable)]) {
        for (key, value) in changes {
            self.changes[AnyHashable(key)] = .value(value)
        }
    }

    // α: The core αuthorizations pool.
    public var coreAuthorizationPool: StateKeys.CoreAuthorizationPoolKey.Value {
        get {
            changes[StateKeys.CoreAuthorizationPoolKey()]!.value()!
        }
        set {
            changes[StateKeys.CoreAuthorizationPoolKey()] = .init(newValue)
        }
    }

    // φ: The authorization queue.
    public var authorizationQueue: StateKeys.AuthorizationQueueKey.Value {
        get {
            changes[StateKeys.AuthorizationQueueKey()]!.value()!
        }
        set {
            changes[StateKeys.AuthorizationQueueKey()] = .init(newValue)
        }
    }

    // β: Information on the most recent βlocks.
    public var recentHistory: StateKeys.RecentHistoryKey.Value {
        get {
            changes[StateKeys.RecentHistoryKey()]!.value()!
        }
        set {
            changes[StateKeys.RecentHistoryKey()] = .init(newValue)
        }
    }

    // γ: State concerning Safrole.
    public var safroleState: StateKeys.SafroleStateKey.Value {
        get {
            changes[StateKeys.SafroleStateKey()]!.value()!
        }
        set {
            changes[StateKeys.SafroleStateKey()] = .init(newValue)
        }
    }

    // ψ: past judgements
    public var judgements: StateKeys.JudgementsKey.Value {
        get {
            changes[StateKeys.JudgementsKey()]!.value()!
        }
        set {
            changes[StateKeys.JudgementsKey()] = .init(newValue)
        }
    }

    // η: The eηtropy accumulator and epochal raηdomness.
    public var entropyPool: StateKeys.EntropyPoolKey.Value {
        get {
            changes[StateKeys.EntropyPoolKey()]!.value()!
        }
        set {
            changes[StateKeys.EntropyPoolKey()] = .init(newValue)
        }
    }

    // ι: The validator keys and metadata to be drawn from next.
    public var validatorQueue: StateKeys.ValidatorQueueKey.Value {
        get {
            changes[StateKeys.ValidatorQueueKey()]!.value()!
        }
        set {
            changes[StateKeys.ValidatorQueueKey()] = .init(newValue)
        }
    }

    // κ: The validator κeys and metadata currently active.
    public var currentValidators: StateKeys.CurrentValidatorsKey.Value {
        get {
            changes[StateKeys.CurrentValidatorsKey()]!.value()!
        }
        set {
            changes[StateKeys.CurrentValidatorsKey()] = .init(newValue)
        }
    }

    // λ: The validator keys and metadata which were active in the prior epoch.
    public var previousValidators: StateKeys.PreviousValidatorsKey.Value {
        get {
            changes[StateKeys.PreviousValidatorsKey()]!.value()!
        }
        set {
            changes[StateKeys.PreviousValidatorsKey()] = .init(newValue)
        }
    }

    // ρ: The ρending reports, per core, which are being made available prior to accumulation.
    public var reports: StateKeys.ReportsKey.Value {
        get {
            changes[StateKeys.ReportsKey()]!.value()!
        }
        set {
            changes[StateKeys.ReportsKey()] = .init(newValue)
        }
    }

    // τ: The most recent block’s τimeslot.
    public var timeslot: StateKeys.TimeslotKey.Value {
        get {
            changes[StateKeys.TimeslotKey()]!.value()!
        }
        set {
            changes[StateKeys.TimeslotKey()] = .init(newValue)
        }
    }

    // χ: The privileged service indices.
    public var privilegedServices: StateKeys.PrivilegedServicesKey.Value {
        get {
            changes[StateKeys.PrivilegedServicesKey()]!.value()!
        }
        set {
            changes[StateKeys.PrivilegedServicesKey()] = .init(newValue)
        }
    }

    // π: The activity statistics for the validators.
    public var activityStatistics: StateKeys.ActivityStatisticsKey.Value {
        get {
            changes[StateKeys.ActivityStatisticsKey()]!.value()!
        }
        set {
            changes[StateKeys.ActivityStatisticsKey()] = .init(newValue)
        }
    }

    // ϑ: The accumulation queue.
    public var accumulationQueue: StateKeys.AccumulationQueueKey.Value {
        get {
            changes[StateKeys.AccumulationQueueKey()]!.value()!
        }
        set {
            changes[StateKeys.AccumulationQueueKey()] = .init(newValue)
        }
    }

    // ξ: The accumulation history.
    public var accumulationHistory: StateKeys.AccumulationHistoryKey.Value {
        get {
            changes[StateKeys.AccumulationHistoryKey()]!.value()!
        }
        set {
            changes[StateKeys.AccumulationHistoryKey()] = .init(newValue)
        }
    }

    // δ: The (prior) state of the service accounts.
    public subscript(serviceAccount index: ServiceIndex) -> StateKeys.ServiceAccountKey.Value? {
        get {
            changes[StateKeys.ServiceAccountKey(index: index)]?.value()
        }
        set {
            changes[StateKeys.ServiceAccountKey(index: index)] = .init(newValue)
        }
    }

    // s
    public subscript(serviceAccount index: ServiceIndex, storageKey key: Data32) -> StateKeys.ServiceAccountStorageKey.Value? {
        get {
            changes[StateKeys.ServiceAccountStorageKey(index: index, key: key)]?.value()
        }
        set {
            changes[StateKeys.ServiceAccountStorageKey(index: index, key: key)] = .init(newValue)
        }
    }

    // p
    public subscript(
        serviceAccount index: ServiceIndex, preimageHash hash: Data32
    ) -> StateKeys.ServiceAccountPreimagesKey.Value? {
        get {
            changes[StateKeys.ServiceAccountPreimagesKey(index: index, hash: hash)]?.value()
        }
        set {
            changes[StateKeys.ServiceAccountPreimagesKey(index: index, hash: hash)] = .init(newValue)
        }
    }

    // l
    public subscript(
        serviceAccount index: ServiceIndex, preimageHash hash: Data32, length length: UInt32
    ) -> StateKeys.ServiceAccountPreimageInfoKey.Value? {
        get {
            changes[
                StateKeys.ServiceAccountPreimageInfoKey(index: index, hash: hash, length: length)
            ]?.value()
        }
        set {
            changes[StateKeys.ServiceAccountPreimageInfoKey(index: index, hash: hash, length: length)] = .init(newValue)
        }
    }
}

extension StateLayer {
    public func toKV() -> some Sequence<(key: any StateKey, value: (Codable & Sendable)?)> {
        changes.map { (key: $0.key.base as! any StateKey, value: $0.value.value()) }
    }
}

extension StateLayer {
    public func read<Key: StateKey>(_ key: Key) -> Key.Value? {
        changes[key] as? Key.Value
    }

    public mutating func write<Key: StateKey>(_ key: Key, value: Key.Value?) {
        changes[key] = .init(value)
    }

    public subscript(key: any StateKey) -> (Codable & Sendable)? {
        get {
            changes[AnyHashable(key)]?.value()
        }
        set {
            changes[AnyHashable(key)] = .init(newValue)
        }
    }
}
