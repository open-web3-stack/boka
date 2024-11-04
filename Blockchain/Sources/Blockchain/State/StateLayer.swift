import Foundation
import Utils

// @unchecked because AnyHashable is not Sendable
public struct StateLayer: @unchecked Sendable {
    private var changes: [AnyHashable: Codable & Sendable] = [:]

    public init(backend: StateBackend) async throws {
        let keys: [any StateKey] = [
            StateKeys.CoreAuthorizationPoolKey(),
            StateKeys.AuthorizationQueueKey(),
            StateKeys.RecentHistoryKey(),
            StateKeys.SafroleStateKey(),
            StateKeys.JudgementsKey(),
            StateKeys.EntropyPoolKey(),
            StateKeys.ValidatorQueueKey(),
            StateKeys.CurrentValidatorsKey(),
            StateKeys.PreviousValidatorsKey(),
            StateKeys.ReportsKey(),
            StateKeys.TimeslotKey(),
            StateKeys.PrivilegedServicesKey(),
            StateKeys.ActivityStatisticsKey(),
        ]

        let results = try await backend.batchRead(keys)

        for (key, value) in results {
            changes[AnyHashable(key)] = value
        }
    }

    public init(changes: [(key: any StateKey, value: Codable & Sendable)]) {
        for (key, value) in changes {
            self.changes[AnyHashable(key)] = value
        }
    }

    // α: The core αuthorizations pool.
    public var coreAuthorizationPool: StateKeys.CoreAuthorizationPoolKey.Value.ValueType {
        get {
            changes[StateKeys.CoreAuthorizationPoolKey()] as! StateKeys.CoreAuthorizationPoolKey.Value.ValueType
        }
        set {
            changes[StateKeys.CoreAuthorizationPoolKey()] = newValue
        }
    }

    // φ: The authorization queue.
    public var authorizationQueue: StateKeys.AuthorizationQueueKey.Value.ValueType {
        get {
            changes[StateKeys.AuthorizationQueueKey()] as! StateKeys.AuthorizationQueueKey.Value.ValueType
        }
        set {
            changes[StateKeys.AuthorizationQueueKey()] = newValue
        }
    }

    // β: Information on the most recent βlocks.
    public var recentHistory: StateKeys.RecentHistoryKey.Value.ValueType {
        get {
            changes[StateKeys.RecentHistoryKey()] as! StateKeys.RecentHistoryKey.Value.ValueType
        }
        set {
            changes[StateKeys.RecentHistoryKey()] = newValue
        }
    }

    // γ: State concerning Safrole.
    public var safroleState: StateKeys.SafroleStateKey.Value.ValueType {
        get {
            changes[StateKeys.SafroleStateKey()] as! StateKeys.SafroleStateKey.Value.ValueType
        }
        set {
            changes[StateKeys.SafroleStateKey()] = newValue
        }
    }

    // ψ: past judgements
    public var judgements: StateKeys.JudgementsKey.Value.ValueType {
        get {
            changes[StateKeys.JudgementsKey()] as! StateKeys.JudgementsKey.Value.ValueType
        }
        set {
            changes[StateKeys.JudgementsKey()] = newValue
        }
    }

    // η: The eηtropy accumulator and epochal raηdomness.
    public var entropyPool: StateKeys.EntropyPoolKey.Value.ValueType {
        get {
            changes[StateKeys.EntropyPoolKey()] as! StateKeys.EntropyPoolKey.Value.ValueType
        }
        set {
            changes[StateKeys.EntropyPoolKey()] = newValue
        }
    }

    // ι: The validator keys and metadata to be drawn from next.
    public var validatorQueue: StateKeys.ValidatorQueueKey.Value.ValueType {
        get {
            changes[StateKeys.ValidatorQueueKey()] as! StateKeys.ValidatorQueueKey.Value.ValueType
        }
        set {
            changes[StateKeys.ValidatorQueueKey()] = newValue
        }
    }

    // κ: The validator κeys and metadata currently active.
    public var currentValidators: StateKeys.CurrentValidatorsKey.Value.ValueType {
        get {
            changes[StateKeys.CurrentValidatorsKey()] as! StateKeys.CurrentValidatorsKey.Value.ValueType
        }
        set {
            changes[StateKeys.CurrentValidatorsKey()] = newValue
        }
    }

    // λ: The validator keys and metadata which were active in the prior epoch.
    public var previousValidators: StateKeys.PreviousValidatorsKey.Value.ValueType {
        get {
            changes[StateKeys.PreviousValidatorsKey()] as! StateKeys.PreviousValidatorsKey.Value.ValueType
        }
        set {
            changes[StateKeys.PreviousValidatorsKey()] = newValue
        }
    }

    // ρ: The ρending reports, per core, which are being made available prior to accumulation.
    public var reports: StateKeys.ReportsKey.Value.ValueType {
        get {
            changes[StateKeys.ReportsKey()] as! StateKeys.ReportsKey.Value.ValueType
        }
        set {
            changes[StateKeys.ReportsKey()] = newValue
        }
    }

    // τ: The most recent block’s τimeslot.
    public var timeslot: StateKeys.TimeslotKey.Value.ValueType {
        get {
            changes[StateKeys.TimeslotKey()] as! StateKeys.TimeslotKey.Value.ValueType
        }
        set {
            changes[StateKeys.TimeslotKey()] = newValue
        }
    }

    // χ: The privileged service indices.
    public var privilegedServices: StateKeys.PrivilegedServicesKey.Value.ValueType {
        get {
            changes[StateKeys.PrivilegedServicesKey()] as! StateKeys.PrivilegedServicesKey.Value.ValueType
        }
        set {
            changes[StateKeys.PrivilegedServicesKey()] = newValue
        }
    }

    // π: The activity statistics for the validators.
    public var activityStatistics: StateKeys.ActivityStatisticsKey.Value.ValueType {
        get {
            changes[StateKeys.ActivityStatisticsKey()] as! StateKeys.ActivityStatisticsKey.Value.ValueType
        }
        set {
            changes[StateKeys.ActivityStatisticsKey()] = newValue
        }
    }

    // δ: The (prior) state of the service accounts.
    public subscript(serviceAccount index: ServiceIndex) -> StateKeys.ServiceAccountKey.Value.ValueType? {
        get {
            changes[StateKeys.ServiceAccountKey(index: index)] as? StateKeys.ServiceAccountKey.Value.ValueType
        }
        set {
            changes[StateKeys.ServiceAccountKey(index: index)] = newValue
        }
    }

    // s
    public subscript(serviceAccount index: ServiceIndex, storageKey key: Data32) -> StateKeys.ServiceAccountStorageKey.Value.ValueType? {
        get {
            changes[StateKeys.ServiceAccountStorageKey(index: index, key: key)] as? StateKeys.ServiceAccountStorageKey.Value.ValueType
        }
        set {
            changes[StateKeys.ServiceAccountStorageKey(index: index, key: key)] = newValue
        }
    }

    // p
    public subscript(
        serviceAccount index: ServiceIndex, preimageHash hash: Data32
    ) -> StateKeys.ServiceAccountPreimagesKey.Value.ValueType? {
        get {
            changes[StateKeys.ServiceAccountPreimagesKey(index: index, hash: hash)] as? StateKeys.ServiceAccountPreimagesKey.Value.ValueType
        }
        set {
            changes[StateKeys.ServiceAccountPreimagesKey(index: index, hash: hash)] = newValue
        }
    }

    // l
    public subscript(
        serviceAccount index: ServiceIndex, preimageHash hash: Data32, length length: UInt32
    ) -> StateKeys.ServiceAccountPreimageInfoKey.Value.ValueType? {
        get {
            changes[
                StateKeys.ServiceAccountPreimageInfoKey(index: index, hash: hash, length: length)
            ] as? StateKeys.ServiceAccountPreimageInfoKey.Value.ValueType
        }
        set {
            changes[StateKeys.ServiceAccountPreimageInfoKey(index: index, hash: hash, length: length)] = newValue
        }
    }
}

extension StateLayer {
    public func toKV() -> some Sequence<(key: any StateKey, value: Any)> {
        changes.map { (key: $0.key.base as! any StateKey, value: $0.value) }
    }
}

extension StateLayer {
    public func read<Key: StateKey>(_ key: Key) -> Key.Value.ValueType? {
        changes[key] as? Key.Value.ValueType
    }

    public mutating func write<Key: StateKey>(_ key: Key, value: Key.Value.ValueType) {
        changes[key] = value
    }

    public subscript(key: any StateKey) -> (Codable & Sendable)? {
        get {
            changes[AnyHashable(key)]
        }
        set {
            changes[AnyHashable(key)] = newValue
        }
    }
}
