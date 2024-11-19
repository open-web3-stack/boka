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
public struct StateLayer: Sendable {
    private var changes: [Data32: StateLayerValue] = [:]

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

    // α: The core αuthorizations pool.
    public var coreAuthorizationPool: StateKeys.CoreAuthorizationPoolKey.Value {
        get {
            changes[StateKeys.CoreAuthorizationPoolKey().encode()]!.value()!
        }
        set {
            changes[StateKeys.CoreAuthorizationPoolKey().encode()] = .init(newValue)
        }
    }

    // φ: The authorization queue.
    public var authorizationQueue: StateKeys.AuthorizationQueueKey.Value {
        get {
            changes[StateKeys.AuthorizationQueueKey().encode()]!.value()!
        }
        set {
            changes[StateKeys.AuthorizationQueueKey().encode()] = .init(newValue)
        }
    }

    // β: Information on the most recent βlocks.
    public var recentHistory: StateKeys.RecentHistoryKey.Value {
        get {
            changes[StateKeys.RecentHistoryKey().encode()]!.value()!
        }
        set {
            changes[StateKeys.RecentHistoryKey().encode()] = .init(newValue)
        }
    }

    // γ: State concerning Safrole.
    public var safroleState: StateKeys.SafroleStateKey.Value {
        get {
            changes[StateKeys.SafroleStateKey().encode()]!.value()!
        }
        set {
            changes[StateKeys.SafroleStateKey().encode()] = .init(newValue)
        }
    }

    // ψ: past judgements
    public var judgements: StateKeys.JudgementsKey.Value {
        get {
            changes[StateKeys.JudgementsKey().encode()]!.value()!
        }
        set {
            changes[StateKeys.JudgementsKey().encode()] = .init(newValue)
        }
    }

    // η: The eηtropy accumulator and epochal raηdomness.
    public var entropyPool: StateKeys.EntropyPoolKey.Value {
        get {
            changes[StateKeys.EntropyPoolKey().encode()]!.value()!
        }
        set {
            changes[StateKeys.EntropyPoolKey().encode()] = .init(newValue)
        }
    }

    // ι: The validator keys and metadata to be drawn from next.
    public var validatorQueue: StateKeys.ValidatorQueueKey.Value {
        get {
            changes[StateKeys.ValidatorQueueKey().encode()]!.value()!
        }
        set {
            changes[StateKeys.ValidatorQueueKey().encode()] = .init(newValue)
        }
    }

    // κ: The validator κeys and metadata currently active.
    public var currentValidators: StateKeys.CurrentValidatorsKey.Value {
        get {
            changes[StateKeys.CurrentValidatorsKey().encode()]!.value()!
        }
        set {
            changes[StateKeys.CurrentValidatorsKey().encode()] = .init(newValue)
        }
    }

    // λ: The validator keys and metadata which were active in the prior epoch.
    public var previousValidators: StateKeys.PreviousValidatorsKey.Value {
        get {
            changes[StateKeys.PreviousValidatorsKey().encode()]!.value()!
        }
        set {
            changes[StateKeys.PreviousValidatorsKey().encode()] = .init(newValue)
        }
    }

    // ρ: The ρending reports, per core, which are being made available prior to accumulation.
    public var reports: StateKeys.ReportsKey.Value {
        get {
            changes[StateKeys.ReportsKey().encode()]!.value()!
        }
        set {
            changes[StateKeys.ReportsKey().encode()] = .init(newValue)
        }
    }

    // τ: The most recent block’s τimeslot.
    public var timeslot: StateKeys.TimeslotKey.Value {
        get {
            changes[StateKeys.TimeslotKey().encode()]!.value()!
        }
        set {
            changes[StateKeys.TimeslotKey().encode()] = .init(newValue)
        }
    }

    // χ: The privileged service indices.
    public var privilegedServices: StateKeys.PrivilegedServicesKey.Value {
        get {
            changes[StateKeys.PrivilegedServicesKey().encode()]!.value()!
        }
        set {
            changes[StateKeys.PrivilegedServicesKey().encode()] = .init(newValue)
        }
    }

    // π: The activity statistics for the validators.
    public var activityStatistics: StateKeys.ActivityStatisticsKey.Value {
        get {
            changes[StateKeys.ActivityStatisticsKey().encode()]!.value()!
        }
        set {
            changes[StateKeys.ActivityStatisticsKey().encode()] = .init(newValue)
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

    // s
    public subscript(serviceAccount index: ServiceIndex, storageKey key: Data32) -> StateKeys.ServiceAccountStorageKey.Value? {
        get {
            changes[StateKeys.ServiceAccountStorageKey(index: index, key: key).encode()]?.value()
        }
        set {
            changes[StateKeys.ServiceAccountStorageKey(index: index, key: key).encode()] = .init(newValue)
        }
    }

    // p
    public subscript(
        serviceAccount index: ServiceIndex, preimageHash hash: Data32
    ) -> StateKeys.ServiceAccountPreimagesKey.Value? {
        get {
            changes[StateKeys.ServiceAccountPreimagesKey(index: index, hash: hash).encode()]?.value()
        }
        set {
            changes[StateKeys.ServiceAccountPreimagesKey(index: index, hash: hash).encode()] = .init(newValue)
        }
    }

    // l
    public subscript(
        serviceAccount index: ServiceIndex, preimageHash hash: Data32, length length: UInt32
    ) -> StateKeys.ServiceAccountPreimageInfoKey.Value? {
        get {
            changes[
                StateKeys.ServiceAccountPreimageInfoKey(
                    index: index, hash: hash, length: length
                ).encode()
            ]?.value()
        }
        set {
            changes[
                StateKeys.ServiceAccountPreimageInfoKey(
                    index: index, hash: hash, length: length
                ).encode()
            ] = .init(newValue)
        }
    }
}

extension StateLayer {
    public func toKV() -> some Sequence<(key: Data32, value: (Codable & Sendable)?)> {
        changes.map { (key: $0.key, value: $0.value.value()) }
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

    public subscript(key: Data32) -> (Codable & Sendable)? {
        get {
            changes[key]?.value()
        }
        set {
            changes[key] = .init(newValue)
        }
    }
}
