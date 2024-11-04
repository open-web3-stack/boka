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

    // α: The core αuthorizations pool.
    public var coreAuthorizationPool: StateKeys.CoreAuthorizationPoolKey.Value.ValueType {
        get {
            layer.coreAuthorizationPool
        }
        set {
            layer.coreAuthorizationPool = newValue
        }
    }

    // φ: The authorization queue.
    public var authorizationQueue: StateKeys.AuthorizationQueueKey.Value.ValueType {
        get {
            layer.authorizationQueue
        }
        set {
            layer.authorizationQueue = newValue
        }
    }

    // β: Information on the most recent βlocks.
    public var recentHistory: StateKeys.RecentHistoryKey.Value.ValueType {
        get {
            layer.recentHistory
        }
        set {
            layer.recentHistory = newValue
        }
    }

    // γ: State concerning Safrole.
    public var safroleState: StateKeys.SafroleStateKey.Value.ValueType {
        get {
            layer.safroleState
        }
        set {
            layer.safroleState = newValue
        }
    }

    // ψ: past judgements
    public var judgements: StateKeys.JudgementsKey.Value.ValueType {
        get {
            layer.judgements
        }
        set {
            layer.judgements = newValue
        }
    }

    // η: The eηtropy accumulator and epochal raηdomness.
    public var entropyPool: StateKeys.EntropyPoolKey.Value.ValueType {
        get {
            layer.entropyPool
        }
        set {
            layer.entropyPool = newValue
        }
    }

    // ι: The validator keys and metadata to be drawn from next.
    public var validatorQueue: StateKeys.ValidatorQueueKey.Value.ValueType {
        get {
            layer.validatorQueue
        }
        set {
            layer.validatorQueue = newValue
        }
    }

    // κ: The validator κeys and metadata currently active.
    public var currentValidators: StateKeys.CurrentValidatorsKey.Value.ValueType {
        get {
            layer.currentValidators
        }
        set {
            layer.currentValidators = newValue
        }
    }

    // λ: The validator keys and metadata which were active in the prior epoch.
    public var previousValidators: StateKeys.PreviousValidatorsKey.Value.ValueType {
        get {
            layer.previousValidators
        }
        set {
            layer.previousValidators = newValue
        }
    }

    // ρ: The ρending reports, per core, which are being made available prior to accumulation.
    public var reports: StateKeys.ReportsKey.Value.ValueType {
        get {
            layer.reports
        }
        set {
            layer.reports = newValue
        }
    }

    // τ: The most recent block’s τimeslot.
    public var timeslot: StateKeys.TimeslotKey.Value.ValueType {
        get {
            layer.timeslot
        }
        set {
            layer.timeslot = newValue
        }
    }

    // χ: The privileged service indices.
    public var privilegedServices: StateKeys.PrivilegedServicesKey.Value.ValueType {
        get {
            layer.privilegedServices
        }
        set {
            layer.privilegedServices = newValue
        }
    }

    // π: The activity statistics for the validators.
    public var activityStatistics: StateKeys.ActivityStatisticsKey.Value.ValueType {
        get {
            layer.activityStatistics
        }
        set {
            layer.activityStatistics = newValue
        }
    }

    // δ: The (prior) state of the service accounts.
    public subscript(serviceAccount index: ServiceIndex) -> StateKeys.ServiceAccountKey.Value.ValueType? {
        get {
            layer[serviceAccount: index]
        }
        set {
            layer[serviceAccount: index] = newValue
        }
    }

    // s
    public subscript(serviceAccount index: ServiceIndex, storageKey key: Data32) -> StateKeys.ServiceAccountStorageKey.Value.ValueType? {
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
    ) -> StateKeys.ServiceAccountPreimagesKey.Value.ValueType? {
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
    ) -> StateKeys.ServiceAccountPreimageInfoKey.Value.ValueType? {
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

    public func stateRoot() -> Data32 {
        // TODO: incorporate layer changes and calculate state root
        Data32()
    }
}

extension State {
    public var lastBlockHash: Data32 {
        recentHistory.items.last.map(\.headerHash)!
    }

    private class KVSequence: Sequence {
        typealias Element = (key: Data32, value: Data)

        let seq: any Sequence<(key: Data32, value: Data)>
        let layer: [Data32: Data]

        init(state: State) async throws {
            seq = try await state.backend.readAll()
            var layer = [Data32: Data]()
            for (key, value) in state.layer.toKV() {
                layer[key.encode()] = try JamEncoder.encode(value)
            }
            self.layer = layer
        }

        func makeIterator() -> KVSequence.Iterator {
            KVSequence.Iterator(iter: seq.makeIterator(), layer: layer)
        }

        struct Iterator: IteratorProtocol {
            typealias Element = (key: Data32, value: Data)

            var iter: any IteratorProtocol<KVSequence.Element>
            var layerIterator: (any IteratorProtocol<KVSequence.Element>)?
            let layer: [Data32: Data]

            init(iter: any IteratorProtocol<KVSequence.Element>, layer: [Data32: Data]) {
                self.iter = iter
                self.layer = layer
            }

            mutating func next() -> KVSequence.Iterator.Element? {
                if layerIterator != nil {
                    return layerIterator?.next()
                }
                if let (key, value) = iter.next() {
                    if layer[key] != nil {
                        return next() // skip this one
                    }
                    return (key, value)
                }
                layerIterator = layer.makeIterator()
                return layerIterator?.next()
            }
        }
    }

    public func toKV() async throws -> some Sequence<(key: Data32, value: Data)> {
        try await KVSequence(state: self)
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
        let coreAuthorizationPool: StateKeys.CoreAuthorizationPoolKey.Value.ValueType =
            try! ConfigFixedSizeArray(config: config, defaultValue: ConfigLimitedSizeArray(config: config))
        var recentHistory: StateKeys.RecentHistoryKey.Value.ValueType = RecentHistory.dummy(config: config)
        if let block {
            recentHistory.items.safeAppend(RecentHistory.HistoryItem(
                headerHash: block.hash,
                mmr: MMR([]),
                stateRoot: Data32(),
                workReportHashes: try! ConfigLimitedSizeArray(config: config)
            ))
        }
        let safroleState: StateKeys.SafroleStateKey.Value.ValueType = SafroleState.dummy(config: config)
        let entropyPool: StateKeys.EntropyPoolKey.Value.ValueType = EntropyPool((Data32(), Data32(), Data32(), Data32()))
        let validatorQueue: StateKeys.ValidatorQueueKey.Value.ValueType =
            try! ConfigFixedSizeArray(config: config, defaultValue: ValidatorKey.dummy(config: config))
        let currentValidators: StateKeys.CurrentValidatorsKey.Value.ValueType =
            try! ConfigFixedSizeArray(config: config, defaultValue: ValidatorKey.dummy(config: config))
        let previousValidators: StateKeys.PreviousValidatorsKey.Value.ValueType =
            try! ConfigFixedSizeArray(config: config, defaultValue: ValidatorKey.dummy(config: config))
        let reports: StateKeys.ReportsKey.Value.ValueType = try! ConfigFixedSizeArray(config: config, defaultValue: nil)
        let timeslot: StateKeys.TimeslotKey.Value.ValueType = block?.header.timeslot ?? 0
        let authorizationQueue: StateKeys.AuthorizationQueueKey.Value.ValueType =
            try! ConfigFixedSizeArray(config: config, defaultValue: ConfigFixedSizeArray(config: config, defaultValue: Data32()))
        let privilegedServices: StateKeys.PrivilegedServicesKey.Value.ValueType = PrivilegedServices(
            empower: ServiceIndex(),
            assign: ServiceIndex(),
            designate: ServiceIndex(),
            basicGas: [:]
        )
        let judgements: StateKeys.JudgementsKey.Value.ValueType = JudgementsState.dummy(config: config)
        let activityStatistics: StateKeys.ActivityStatisticsKey.Value.ValueType = ValidatorActivityStatistics.dummy(config: config)

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
        ]

        var store: [Data32: Data] = [:]
        for (key, value) in kv {
            store[key.encode()] = try! JamEncoder.encode(value)
        }

        let backend = InMemoryBackend(
            config: config,
            store: store
        )

        let layer = StateLayer(changes: kv)

        return State(backend: backend, layer: layer)
    }
}

extension State: ServiceAccounts {
    public func get(serviceAccount index: ServiceIndex) async throws -> ServiceAccountDetails? {
        if let res = layer[serviceAccount: index] {
            return res
        }
        return try await backend.read(StateKeys.ServiceAccountKey(index: index))
    }

    public func get(serviceAccount index: ServiceIndex, storageKey key: Data32) async throws -> Data? {
        if let res = layer[serviceAccount: index, storageKey: key] {
            return res
        }
        return try await backend.read(StateKeys.ServiceAccountStorageKey(index: index, key: key))
    }

    public func get(serviceAccount index: ServiceIndex, preimageHash hash: Data32) async throws -> Data? {
        if let res = layer[serviceAccount: index, preimageHash: hash] {
            return res
        }
        return try await backend.read(StateKeys.ServiceAccountPreimagesKey(index: index, hash: hash))
    }

    public func get(
        serviceAccount index: ServiceIndex, preimageHash hash: Data32, length: UInt32
    ) async throws -> StateKeys.ServiceAccountPreimageInfoKey.Value.ValueType {
        if let res = layer[serviceAccount: index, preimageHash: hash, length: length] {
            return res
        }
        return try await backend.read(StateKeys.ServiceAccountPreimageInfoKey(index: index, hash: hash, length: length))
    }

    public mutating func set(serviceAccount index: ServiceIndex, account: ServiceAccountDetails) {
        layer[serviceAccount: index] = account
    }

    public mutating func set(serviceAccount index: ServiceIndex, storageKey key: Data32, value: Data) {
        layer[serviceAccount: index, storageKey: key] = value
    }

    public mutating func set(serviceAccount index: ServiceIndex, preimageHash hash: Data32, value: Data) {
        layer[serviceAccount: index, preimageHash: hash] = value
    }

    public mutating func set(
        serviceAccount index: ServiceIndex,
        preimageHash hash: Data32,
        length: UInt32,
        value: StateKeys.ServiceAccountPreimageInfoKey.Value.ValueType
    ) {
        layer[serviceAccount: index, preimageHash: hash, length: length] = value
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

extension State: Disputes {
    public mutating func mergeWith(postState: DisputePostState) {
        judgements = postState.judgements
        reports = postState.reports
    }
}

extension State: Guaranteeing {
    public var offenders: Set<Ed25519PublicKey> {
        judgements.punishSet
    }

    public func serviceAccount(index: ServiceIndex) -> ServiceAccountDetails? {
        self[serviceAccount: index] ?? nil
    }
}

struct DummyFunction: AccumulateFunction, OnTransferFunction {
    func invoke(
        config _: ProtocolConfigRef,
        accounts _: ServiceAccounts,
        state _: AccumulateState,
        serviceIndex _: ServiceIndex,
        gas _: Gas,
        arguments _: [AccumulateArguments],
        initialIndex _: ServiceIndex,
        timeslot _: TimeslotIndex
    ) throws -> (state: AccumulateState, transfers: [DeferredTransfers], result: Data32?, gas: Gas) {
        fatalError("not implemented")
    }

    func invoke(
        config _: ProtocolConfigRef,
        service _: ServiceIndex,
        code _: Data,
        serviceAccounts _: [ServiceIndex: ServiceAccount],
        transfers _: [DeferredTransfers]
    ) throws -> ServiceAccount {
        fatalError("not implemented")
    }
}

extension State: Accumulation {
    public var accumlateFunction: AccumulateFunction {
        DummyFunction()
    }

    public var onTransferFunction: OnTransferFunction {
        DummyFunction()
    }
}

public class StateRef: Ref<State>, @unchecked Sendable {
    public static func dummy(config: ProtocolConfigRef, block: BlockRef?) -> StateRef {
        StateRef(State.dummy(config: config, block: block))
    }

    public var stateRoot: Data32 {
        value.stateRoot()
    }
}
