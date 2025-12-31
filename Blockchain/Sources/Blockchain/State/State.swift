import Codec
import Foundation
import Utils

public struct State: Sendable {
    public let backend: StateBackend
    public var layer: StateLayer

    public init(backend: StateBackend) async throws {
        self.backend = backend
        layer = try await StateLayer(backend: backend)
    }

    public init(backend: StateBackend, layer: StateLayer) {
        self.backend = backend
        self.layer = layer
    }

    public init(copying other: State) {
        // backend can be shared as it's read-only until end of stf
        backend = other.backend
        layer = StateLayer(copying: other.layer)
    }

    // α: The core αuthorizations pool.
    public var coreAuthorizationPool: StateKeys.CoreAuthorizationPoolKey.Value {
        get {
            layer.coreAuthorizationPool
        }
        set {
            layer.coreAuthorizationPool = newValue
        }
    }

    // ϕ: The authorization queue.
    public var authorizationQueue: StateKeys.AuthorizationQueueKey.Value {
        get {
            layer.authorizationQueue
        }
        set {
            layer.authorizationQueue = newValue
        }
    }

    // β: Information on the most recent βlocks.
    public var recentHistory: StateKeys.RecentHistoryKey.Value {
        get {
            layer.recentHistory
        }
        set {
            layer.recentHistory = newValue
        }
    }

    // γ: State concerning Safrole.
    public var safroleState: StateKeys.SafroleStateKey.Value {
        get {
            layer.safroleState
        }
        set {
            layer.safroleState = newValue
        }
    }

    // ψ: past judgements
    public var judgements: StateKeys.JudgementsKey.Value {
        get {
            layer.judgements
        }
        set {
            layer.judgements = newValue
        }
    }

    // η: The eηtropy accumulator and epochal raηdomness.
    public var entropyPool: StateKeys.EntropyPoolKey.Value {
        get {
            layer.entropyPool
        }
        set {
            layer.entropyPool = newValue
        }
    }

    // ι: The validator keys and metadata to be drawn from next.
    public var validatorQueue: StateKeys.ValidatorQueueKey.Value {
        get {
            layer.validatorQueue
        }
        set {
            layer.validatorQueue = newValue
        }
    }

    // κ: The validator κeys and metadata currently active.
    public var currentValidators: StateKeys.CurrentValidatorsKey.Value {
        get {
            layer.currentValidators
        }
        set {
            layer.currentValidators = newValue
        }
    }

    // λ: The validator keys and metadata which were active in the prior epoch.
    public var previousValidators: StateKeys.PreviousValidatorsKey.Value {
        get {
            layer.previousValidators
        }
        set {
            layer.previousValidators = newValue
        }
    }

    // ρ: The ρending reports, per core, which are being made available prior to accumulation.
    public var reports: StateKeys.ReportsKey.Value {
        get {
            layer.reports
        }
        set {
            layer.reports = newValue
        }
    }

    // τ: The most recent block’s τimeslot.
    public var timeslot: StateKeys.TimeslotKey.Value {
        get {
            layer.timeslot
        }
        set {
            layer.timeslot = newValue
        }
    }

    // χ: The privileged service indices.
    public var privilegedServices: StateKeys.PrivilegedServicesKey.Value {
        get {
            layer.privilegedServices
        }
        set {
            layer.privilegedServices = newValue
        }
    }

    // π: The activity statistics for the validators.
    public var activityStatistics: StateKeys.ActivityStatisticsKey.Value {
        get {
            layer.activityStatistics
        }
        set {
            layer.activityStatistics = newValue
        }
    }

    // ω: The accumulation queue.
    public var accumulationQueue: StateKeys.AccumulationQueueKey.Value {
        get {
            layer.accumulationQueue
        }
        set {
            layer.accumulationQueue = newValue
        }
    }

    // ξ: The accumulation history.
    public var accumulationHistory: StateKeys.AccumulationHistoryKey.Value {
        get {
            layer.accumulationHistory
        }
        set {
            layer.accumulationHistory = newValue
        }
    }

    // θ: The most recent Accumulation outputs
    public var lastAccumulationOutputs: StateKeys.LastAccumulationOutputsKey.Value {
        get {
            layer.lastAccumulationOutputs
        }
        set {
            layer.lastAccumulationOutputs = newValue
        }
    }

    // δ: The (prior) state of the service accounts.
    public subscript(serviceAccount index: ServiceIndex) -> StateKeys.ServiceAccountKey.Value? {
        get {
            layer[serviceAccount: index]
        }
        set {
            layer[serviceAccount: index] = newValue
        }
    }

    // s
    public subscript(serviceAccount index: ServiceIndex, storageKey key: Data) -> StateKeys.ServiceAccountStorageKey.Value? {
        get {
            layer[serviceAccount: index, storageKey: key]
        }
        set {
            layer[serviceAccount: index, storageKey: key] = newValue
        }
    }

    // p
    public subscript(
        serviceAccount index: ServiceIndex, preimageHash hash: Data32
    ) -> StateKeys.ServiceAccountPreimagesKey.Value? {
        get {
            layer[serviceAccount: index, preimageHash: hash]
        }
        set {
            layer[serviceAccount: index, preimageHash: hash] = newValue
        }
    }

    // l
    public subscript(
        serviceAccount index: ServiceIndex, preimageHash hash: Data32, length length: UInt32
    ) -> StateKeys.ServiceAccountPreimageInfoKey.Value? {
        get {
            layer[serviceAccount: index, preimageHash: hash, length: length]
        }
        set {
            layer[serviceAccount: index, preimageHash: hash, length: length] = newValue
        }
    }

    public mutating func load(keys: [any StateKey]) async throws {
        let pairs = try await backend.batchRead(keys)
        for (key, value) in pairs {
            layer[key] = value
        }
    }

    /// Save state changes to persistent storage
    /// Note: This writes directly to the underlying backend.
    /// Future improvement: Consider using a two-tier approach:
    /// 1. Write to in-memory layer first (faster, allows rollback)
    /// 2. Flush in-memory layer to persistent store on commit
    /// This would improve performance and provide better transaction isolation
    @discardableResult
    public func save() async throws -> Data32 {
        try await backend.write(layer.toKV())
        return await backend.rootHash
    }

    public var stateRoot: Data32 {
        get async {
            await backend.rootHash
        }
    }

    public func read(key: Data31) async throws -> Data? {
        let res = try layer[key].map { try JamEncoder.encode($0) }
        if let res {
            return res
        }
        return try await backend.readRaw(key)
    }
}

extension State {
    public var lastBlockHash: Data32 {
        recentHistory.items.last.map(\.headerHash)!
    }

    public func asRef() -> StateRef {
        StateRef(self)
    }
}

extension State: Dummy {
    public typealias Config = ProtocolConfigRef

    public static func dummy(config: Config) -> State {
        dummy(config: config, block: nil)
    }

    public static func dummy(config: Config, block: BlockRef?) -> State {
        let coreAuthorizationPool: StateKeys.CoreAuthorizationPoolKey.Value =
            try! ConfigFixedSizeArray(config: config, defaultValue: ConfigLimitedSizeArray(config: config))
        var recentHistory: StateKeys.RecentHistoryKey.Value = RecentHistory.dummy(config: config)
        if let block {
            recentHistory.items.safeAppend(RecentHistory.HistoryItem(
                headerHash: block.hash,
                superPeak: Data32(),
                stateRoot: Data32(),
                lookup: [Data32: Data32]()
            ))
        }
        let safroleState: StateKeys.SafroleStateKey.Value = SafroleState.dummy(config: config)
        let entropyPool: StateKeys.EntropyPoolKey.Value = EntropyPool((Data32(), Data32(), Data32(), Data32()))
        let validatorQueue: StateKeys.ValidatorQueueKey.Value =
            try! ConfigFixedSizeArray(config: config, defaultValue: ValidatorKey.dummy(config: config))
        let currentValidators: StateKeys.CurrentValidatorsKey.Value =
            try! ConfigFixedSizeArray(config: config, defaultValue: ValidatorKey.dummy(config: config))
        let previousValidators: StateKeys.PreviousValidatorsKey.Value =
            try! ConfigFixedSizeArray(config: config, defaultValue: ValidatorKey.dummy(config: config))
        let reports: StateKeys.ReportsKey.Value = try! ConfigFixedSizeArray(config: config, defaultValue: nil)
        let timeslot: StateKeys.TimeslotKey.Value = block?.header.timeslot ?? 0
        let authorizationQueue: StateKeys.AuthorizationQueueKey.Value =
            try! ConfigFixedSizeArray(config: config, defaultValue: ConfigFixedSizeArray(config: config, defaultValue: Data32()))
        let privilegedServices: StateKeys.PrivilegedServicesKey.Value = PrivilegedServices(
            manager: ServiceIndex(),
            assigners: try! ConfigFixedSizeArray(config: config, defaultValue: ServiceIndex()),
            delegator: ServiceIndex(),
            registrar: ServiceIndex(),
            alwaysAcc: [:]
        )
        let judgements: StateKeys.JudgementsKey.Value = JudgementsState.dummy(config: config)
        let activityStatistics: StateKeys.ActivityStatisticsKey.Value = Statistics.dummy(config: config)
        let accumulationQueue: StateKeys.AccumulationQueueKey.Value = try! ConfigFixedSizeArray(
            config: config,
            defaultValue: [AccumulationQueueItem]()
        )
        let accumulationHistory: StateKeys.AccumulationHistoryKey.Value = try! ConfigFixedSizeArray(
            config: config,
            defaultValue: .init()
        )
        let lastAccumulationOutputs: StateKeys.LastAccumulationOutputsKey.Value = []

        let kv: [(any StateKey, Codable & Sendable)] = [
            (StateKeys.CoreAuthorizationPoolKey(), coreAuthorizationPool),
            (StateKeys.AuthorizationQueueKey(), authorizationQueue),
            (StateKeys.RecentHistoryKey(), recentHistory),
            (StateKeys.SafroleStateKey(), safroleState),
            (StateKeys.JudgementsKey(), judgements),
            (StateKeys.EntropyPoolKey(), entropyPool),
            (StateKeys.ValidatorQueueKey(), validatorQueue),
            (StateKeys.CurrentValidatorsKey(), currentValidators),
            (StateKeys.PreviousValidatorsKey(), previousValidators),
            (StateKeys.ReportsKey(), reports),
            (StateKeys.TimeslotKey(), timeslot),
            (StateKeys.PrivilegedServicesKey(), privilegedServices),
            (StateKeys.ActivityStatisticsKey(), activityStatistics),
            (StateKeys.AccumulationQueueKey(), accumulationQueue),
            (StateKeys.AccumulationHistoryKey(), accumulationHistory),
            (StateKeys.LastAccumulationOutputsKey(), lastAccumulationOutputs),
        ]

        var store: [Data31: Data] = [:]
        for (key, value) in kv {
            store[key.encode()] = try! JamEncoder.encode(value)
        }
        let rootHash = try! stateMerklize(kv: store)

        let backend = StateBackend(InMemoryBackend(), config: config, rootHash: rootHash)

        let layer = StateLayer(changes: kv)

        return State(backend: backend, layer: layer)
    }
}

extension State: ServiceAccounts {
    public func copy() -> ServiceAccounts {
        State(copying: self)
    }

    public func get(serviceAccount index: ServiceIndex) async throws -> ServiceAccountDetails? {
        if layer.isDeleted(serviceAccount: index) {
            return nil
        }
        if let res = layer[serviceAccount: index] {
            return res
        }
        return try await backend.read(StateKeys.ServiceAccountKey(index: index))
    }

    public func get(serviceAccount index: ServiceIndex, storageKey key: Data) async throws -> Data? {
        if layer.isDeleted(serviceAccount: index, storageKey: key) {
            return nil
        }
        if let res = layer[serviceAccount: index, storageKey: key] {
            return res
        }
        return try await backend.read(StateKeys.ServiceAccountStorageKey(index: index, key: key))
    }

    public func get(serviceAccount index: ServiceIndex, preimageHash hash: Data32) async throws -> Data? {
        if layer.isDeleted(serviceAccount: index, preimageHash: hash) {
            return nil
        }
        if let res = layer[serviceAccount: index, preimageHash: hash] {
            return res
        }
        return try await backend.read(StateKeys.ServiceAccountPreimagesKey(index: index, hash: hash))
    }

    public func get(
        serviceAccount index: ServiceIndex, preimageHash hash: Data32, length: UInt32
    ) async throws -> StateKeys.ServiceAccountPreimageInfoKey.Value? {
        if layer.isDeleted(serviceAccount: index, preimageHash: hash, length: length) {
            return nil
        }
        if let res = layer[serviceAccount: index, preimageHash: hash, length: length] {
            return res
        }
        return try await backend.read(StateKeys.ServiceAccountPreimageInfoKey(index: index, hash: hash, length: length))
    }

    public func historicalLookup(
        serviceAccount index: ServiceIndex,
        timeslot: TimeslotIndex,
        preimageHash hash: Data32
    ) async throws -> Data? {
        if let preimage = try await get(serviceAccount: index, preimageHash: hash),
           let preimageInfo = try await get(serviceAccount: index, preimageHash: hash, length: UInt32(preimage.count))
        {
            var isAvailable = false
            if preimageInfo.count == 1 {
                isAvailable = preimageInfo[0] <= timeslot
            } else if preimageInfo.count == 2 {
                isAvailable = preimageInfo[0] <= timeslot && timeslot < preimageInfo[1]
            } else if preimageInfo.count == 3 {
                isAvailable = preimageInfo[0] <= timeslot && timeslot < preimageInfo[1] && preimageInfo[2] <= timeslot
            }

            return isAvailable ? preimage : nil
        } else {
            return nil
        }
    }

    public mutating func set(serviceAccount index: ServiceIndex, account: ServiceAccountDetails?) {
        layer[serviceAccount: index] = account
    }

    public mutating func set(serviceAccount index: ServiceIndex, storageKey key: Data, value: Data?) async throws {
        // update footprint
        let oldValue = try await get(serviceAccount: index, storageKey: key)
        guard var oldAccount = try await get(serviceAccount: index) else {
            throw StateError.accountNotFound(index: index)
        }

        oldAccount.updateFootprintStorage(key: key, oldValue: oldValue, newValue: value)
        layer[serviceAccount: index] = oldAccount

        // update value
        layer[serviceAccount: index, storageKey: key] = value
    }

    public mutating func set(serviceAccount index: ServiceIndex, preimageHash hash: Data32, value: Data?) {
        layer[serviceAccount: index, preimageHash: hash] = value
    }

    public mutating func set(
        serviceAccount index: ServiceIndex,
        preimageHash hash: Data32,
        length: UInt32,
        value: StateKeys.ServiceAccountPreimageInfoKey.Value?
    ) async throws {
        // update footprint
        let oldValue = try await get(serviceAccount: index, preimageHash: hash, length: length)
        guard var oldAccount = try await get(serviceAccount: index) else {
            throw StateError.accountNotFound(index: index)
        }

        oldAccount.updateFootprintPreimage(oldValue: oldValue, newValue: value, length: length)
        layer[serviceAccount: index] = oldAccount

        // update value
        layer[serviceAccount: index, preimageHash: hash, length: length] = value
    }

    public mutating func remove(serviceAccount index: ServiceIndex) async throws {
        layer[serviceAccount: index] = nil

        let serviceByte = UInt8(index & 0xFF)

        let storageKeyValues = try await backend.getKeys(Data([serviceByte]), nil, nil)
        for (key, _) in storageKeyValues {
            guard let key31 = Data31(key) else { continue }
            if StateKeys.isServiceKey(key31, serviceIndex: index) {
                layer[key31] = nil
            }
        }
    }
}

extension State: Safrole {
    public var nextValidators: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    > { safroleState.nextValidators }

    public var ticketsAccumulator: ConfigLimitedSizeArray<
        Ticket,
        ProtocolConfig.Int0,
        ProtocolConfig.EpochLength
    > { safroleState.ticketsAccumulator }

    public var ticketsOrKeys: Either<
        ConfigFixedSizeArray<
            Ticket,
            ProtocolConfig.EpochLength
        >,
        ConfigFixedSizeArray<
            BandersnatchPublicKey,
            ProtocolConfig.EpochLength
        >
    > { safroleState.ticketsOrKeys }

    public var ticketsVerifier: BandersnatchRingVRFRoot { safroleState.ticketsVerifier }

    public mutating func mergeWith(postState: SafrolePostState) {
        safroleState.nextValidators = postState.nextValidators
        safroleState.ticketsVerifier = postState.ticketsVerifier
        safroleState.ticketsOrKeys = postState.ticketsOrKeys
        safroleState.ticketsAccumulator = postState.ticketsAccumulator
        entropyPool = postState.entropyPool
        validatorQueue = postState.validatorQueue
        currentValidators = postState.currentValidators
        previousValidators = postState.previousValidators
        timeslot = postState.timeslot
    }
}

extension State: Assurances {}

extension State: Disputes {
    public mutating func mergeWith(postState: DisputesPostState) {
        judgements = postState.judgements
        reports = postState.reports
    }
}

extension State: Guaranteeing {
    public var offenders: Set<Ed25519PublicKey> {
        judgements.punishSet
    }

    public func serviceAccount(index: ServiceIndex) async throws -> ServiceAccountDetails? {
        try await get(serviceAccount: index)
    }
}

extension State: Authorization {
    public mutating func mergeWith(postState: AuthorizationPostState) {
        coreAuthorizationPool = postState.coreAuthorizationPool
    }
}

extension State: ActivityStatistics {}

extension State: Preimages {
    public mutating func mergeWith(postState: PreimagesPostState) async throws {
        for update in postState.updates {
            self[serviceAccount: update.serviceIndex, preimageHash: update.hash] = update.data
            self[serviceAccount: update.serviceIndex, preimageHash: update.hash, length: update.length] =
                LimitedSizeArray([update.timeslot])
        }
    }
}

extension State: Accumulation {}

extension State: CustomStringConvertible {
    public var description: String {
        // Note: State objects are complex with nested data structures.
        // Showing the state root hash would be useful for debugging, but caching
        // it would require memory overhead and synchronization.
        // Current: Shows generic "State()" identifier
        // Future: Consider async description or debug-specific representation
        "State()"
    }
}

// MARK: - Errors

public enum StateError: Error {
    case accountNotFound(index: ServiceIndex)
    case backendError(String)
}

/// Reference wrapper for State
///
/// Thread-safety: @unchecked Sendable is inherited from Ref<T>
/// which provides its own synchronization for value access
public class StateRef: Ref<State>, @unchecked Sendable {
    public static func dummy(config: ProtocolConfigRef, block: BlockRef?) -> StateRef {
        StateRef(State.dummy(config: config, block: block))
    }
}
