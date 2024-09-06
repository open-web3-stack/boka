import Codec
import Utils

public struct State: Sendable, Equatable, Codable {
    public struct PrivilegedServiceIndices: Sendable, Equatable, Codable {
        public var empower: ServiceIndex
        public var assign: ServiceIndex
        public var designate: ServiceIndex

        public init(empower: ServiceIndex, assign: ServiceIndex, designate: ServiceIndex) {
            self.empower = empower
            self.assign = assign
            self.designate = designate
        }
    }

    // α: The core αuthorizations pool.
    public var coreAuthorizationPool: ConfigFixedSizeArray<
        ConfigLimitedSizeArray<
            Data32,
            ProtocolConfig.Int0,
            ProtocolConfig.MaxAuthorizationsPoolItems
        >,
        ProtocolConfig.TotalNumberOfCores
    >

    // β: Information on the most recent βlocks.
    public var recentHistory: RecentHistory

    // γ: State concerning Safrole.
    public var safroleState: SafroleState

    // δ: The (prior) state of the service accounts.
    public var serviceAccounts: [ServiceIndex: ServiceAccount]

    // η: The eηtropy accumulator and epochal raηdomness.
    public var entropyPool: EntropyPool

    // ι: The validator keys and metadata to be drawn from next.
    public var validatorQueue: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    >

    // κ: The validator κeys and metadata currently active.
    public var currentValidators: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    >

    // λ: The validator keys and metadata which were active in the prior epoch.
    public var previousValidators: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    >

    // ρ: The ρending reports, per core, which are being made available prior to accumulation.
    public var reports: ConfigFixedSizeArray<
        ReportItem?,
        ProtocolConfig.TotalNumberOfCores
    >

    // τ: The most recent block’s τimeslot.
    public var timeslot: TimeslotIndex

    // φ: The authorization queue.
    public var authorizationQueue: ConfigFixedSizeArray<
        ConfigFixedSizeArray<
            Data32,
            ProtocolConfig.MaxAuthorizationsQueueItems
        >,
        ProtocolConfig.TotalNumberOfCores
    >

    // χ: The privileged service indices.
    public var privilegedServiceIndices: PrivilegedServiceIndices

    // ψ: past judgements
    public var judgements: JudgementsState

    // π: The activity statistics for the validators.
    public var activityStatistics: ValidatorActivityStatistics

    public init(
        coreAuthorizationPool: ConfigFixedSizeArray<
            ConfigLimitedSizeArray<
                Data32,
                ProtocolConfig.Int0,
                ProtocolConfig.MaxAuthorizationsPoolItems
            >,
            ProtocolConfig.TotalNumberOfCores
        >,
        recentHistory: RecentHistory,
        safroleState: SafroleState,
        serviceAccounts: [ServiceIndex: ServiceAccount],
        entropyPool: EntropyPool,
        validatorQueue: ConfigFixedSizeArray<
            ValidatorKey, ProtocolConfig.TotalNumberOfValidators
        >,
        currentValidators: ConfigFixedSizeArray<
            ValidatorKey, ProtocolConfig.TotalNumberOfValidators
        >,
        previousValidators: ConfigFixedSizeArray<
            ValidatorKey, ProtocolConfig.TotalNumberOfValidators
        >,
        reports: ConfigFixedSizeArray<
            ReportItem?,
            ProtocolConfig.TotalNumberOfCores
        >,
        timeslot: TimeslotIndex,
        authorizationQueue: ConfigFixedSizeArray<
            ConfigFixedSizeArray<
                Data32,
                ProtocolConfig.MaxAuthorizationsQueueItems
            >,
            ProtocolConfig.TotalNumberOfCores
        >,
        privilegedServiceIndices: PrivilegedServiceIndices,
        judgements: JudgementsState,
        activityStatistics: ValidatorActivityStatistics
    ) {
        self.coreAuthorizationPool = coreAuthorizationPool
        self.recentHistory = recentHistory
        self.safroleState = safroleState
        self.serviceAccounts = serviceAccounts
        self.entropyPool = entropyPool
        self.validatorQueue = validatorQueue
        self.currentValidators = currentValidators
        self.previousValidators = previousValidators
        self.reports = reports
        self.timeslot = timeslot
        self.authorizationQueue = authorizationQueue
        self.privilegedServiceIndices = privilegedServiceIndices
        self.judgements = judgements
        self.activityStatistics = activityStatistics
    }
}

extension State {
    public var lastBlockHash: Data32 {
        recentHistory.items.last.map(\.headerHash) ?? Data32()
    }
}

extension State: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config: Config) -> State {
        try! State(
            coreAuthorizationPool: ConfigFixedSizeArray(config: config, defaultValue: ConfigLimitedSizeArray(config: config)),
            recentHistory: RecentHistory.dummy(config: config),
            safroleState: SafroleState.dummy(config: config),
            serviceAccounts: [:],
            entropyPool: EntropyPool((Data32(), Data32(), Data32(), Data32())),
            validatorQueue: ConfigFixedSizeArray(config: config, defaultValue: ValidatorKey.dummy(config: config)),
            currentValidators: ConfigFixedSizeArray(config: config, defaultValue: ValidatorKey.dummy(config: config)),
            previousValidators: ConfigFixedSizeArray(config: config, defaultValue: ValidatorKey.dummy(config: config)),
            reports: ConfigFixedSizeArray(config: config, defaultValue: nil),
            timeslot: 0,
            authorizationQueue: ConfigFixedSizeArray(
                config: config,
                defaultValue: ConfigFixedSizeArray(config: config, defaultValue: Data32())
            ),
            privilegedServiceIndices: PrivilegedServiceIndices(
                empower: ServiceIndex(),
                assign: ServiceIndex(),
                designate: ServiceIndex()
            ),
            judgements: JudgementsState.dummy(config: config),
            activityStatistics: ValidatorActivityStatistics.dummy(config: config)
        )
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
}
