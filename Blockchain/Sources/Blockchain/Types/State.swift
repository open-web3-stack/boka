import Codec
import Utils

public struct State: Sendable {
    public struct ReportItem: Sendable, Equatable, Codable {
        public var workReport: WorkReport
        public var timeslot: TimeslotIndex

        public init(
            workReport: WorkReport,
            timeslot: TimeslotIndex
        ) {
            self.workReport = workReport
            self.timeslot = timeslot
        }
    }

    public struct PrivilegedServiceIndices: Sendable, Equatable, Codable {
        public var empower: ServiceIdentifier
        public var assign: ServiceIdentifier
        public var designate: ServiceIdentifier

        public init(empower: ServiceIdentifier, assign: ServiceIdentifier, designate: ServiceIdentifier) {
            self.empower = empower
            self.assign = assign
            self.designate = designate
        }
    }

    public let config: ProtocolConfigRef

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
    public var lastBlock: BlockRef

    // γ: State concerning Safrole.
    public var safroleState: SafroleState

    // δ: The (prior) state of the service accounts.
    public var serviceAccounts: [ServiceIdentifier: ServiceAccount]

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
        config: ProtocolConfigRef,
        coreAuthorizationPool: ConfigFixedSizeArray<
            ConfigLimitedSizeArray<
                Data32,
                ProtocolConfig.Int0,
                ProtocolConfig.MaxAuthorizationsPoolItems
            >,
            ProtocolConfig.TotalNumberOfCores
        >,
        lastBlock: BlockRef,
        safroleState: SafroleState,
        serviceAccounts: [ServiceIdentifier: ServiceAccount],
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
        self.config = config
        self.coreAuthorizationPool = coreAuthorizationPool
        self.lastBlock = lastBlock
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

extension State: Codable {
    enum CodingKeys: String, CodingKey {
        case coreAuthorizationPool
        case lastBlock
        case safroleState
        case serviceAccounts
        case entropyPool
        case validatorQueue
        case currentValidators
        case previousValidators
        case reports
        case timeslot
        case authorizationQueue
        case privilegedServiceIndices
        case judgements
        case activityStatistics
    }

    enum CodingError: Error {
        case missingConfig
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let config = decoder.getConfig(ProtocolConfigRef.self) else {
            throw CodingError.missingConfig
        }
        try self.init(
            config: config,
            coreAuthorizationPool: container.decode(
                ConfigFixedSizeArray<
                    ConfigLimitedSizeArray<
                        Data32,
                        ProtocolConfig.Int0,
                        ProtocolConfig.MaxAuthorizationsPoolItems
                    >,
                    ProtocolConfig.TotalNumberOfCores
                >.self,
                forKey: .coreAuthorizationPool
            ),
            lastBlock: container.decode(BlockRef.self, forKey: .lastBlock),
            safroleState: container.decode(SafroleState.self, forKey: .safroleState),
            serviceAccounts: container.decode([ServiceIdentifier: ServiceAccount].self, forKey: .serviceAccounts),
            entropyPool: container.decode(EntropyPool.self, forKey: .entropyPool),
            validatorQueue: container.decode(
                ConfigFixedSizeArray<
                    ValidatorKey, ProtocolConfig.TotalNumberOfValidators
                >.self,
                forKey: .validatorQueue
            ),
            currentValidators: container.decode(
                ConfigFixedSizeArray<
                    ValidatorKey, ProtocolConfig.TotalNumberOfValidators
                >.self,
                forKey: .currentValidators
            ),
            previousValidators: container.decode(
                ConfigFixedSizeArray<
                    ValidatorKey, ProtocolConfig.TotalNumberOfValidators
                >.self,
                forKey: .previousValidators
            ),
            reports: container.decode(
                ConfigFixedSizeArray<
                    ReportItem?,
                    ProtocolConfig.TotalNumberOfCores
                >.self,
                forKey: .reports
            ),
            timeslot: container.decode(TimeslotIndex.self, forKey: .timeslot),
            authorizationQueue: container.decode(
                ConfigFixedSizeArray<
                    ConfigFixedSizeArray<
                        Data32,
                        ProtocolConfig.MaxAuthorizationsQueueItems
                    >,
                    ProtocolConfig.TotalNumberOfCores
                >.self,
                forKey: .authorizationQueue
            ),
            privilegedServiceIndices: container.decode(PrivilegedServiceIndices.self, forKey: .privilegedServiceIndices),
            judgements: container.decode(JudgementsState.self, forKey: .judgements),
            activityStatistics: container.decode(ValidatorActivityStatistics.self, forKey: .activityStatistics)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(coreAuthorizationPool, forKey: .coreAuthorizationPool)
        try container.encode(lastBlock, forKey: .lastBlock)
        try container.encode(safroleState, forKey: .safroleState)
        try container.encode(serviceAccounts, forKey: .serviceAccounts)
        try container.encode(entropyPool, forKey: .entropyPool)
        try container.encode(validatorQueue, forKey: .validatorQueue)
        try container.encode(currentValidators, forKey: .currentValidators)
        try container.encode(previousValidators, forKey: .previousValidators)
        try container.encode(reports, forKey: .reports)
        try container.encode(timeslot, forKey: .timeslot)
        try container.encode(authorizationQueue, forKey: .authorizationQueue)
        try container.encode(privilegedServiceIndices, forKey: .privilegedServiceIndices)
        try container.encode(judgements, forKey: .judgements)
        try container.encode(activityStatistics, forKey: .activityStatistics)
    }
}

public typealias StateRef = Ref<State>

extension State: Equatable {
    public static func == (lhs: State, rhs: State) -> Bool {
        lhs.coreAuthorizationPool == rhs.coreAuthorizationPool &&
            lhs.lastBlock == rhs.lastBlock &&
            lhs.safroleState == rhs.safroleState &&
            lhs.serviceAccounts == rhs.serviceAccounts &&
            lhs.entropyPool == rhs.entropyPool &&
            lhs.validatorQueue == rhs.validatorQueue &&
            lhs.currentValidators == rhs.currentValidators &&
            lhs.previousValidators == rhs.previousValidators &&
            lhs.reports == rhs.reports &&
            lhs.timeslot == rhs.timeslot &&
            lhs.authorizationQueue == rhs.authorizationQueue &&
            lhs.privilegedServiceIndices == rhs.privilegedServiceIndices &&
            lhs.judgements == rhs.judgements &&
            lhs.activityStatistics == rhs.activityStatistics
    }
}

extension State: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config: Config) -> State {
        try! State(
            config: config,
            coreAuthorizationPool: ConfigFixedSizeArray(config: config, defaultValue: ConfigLimitedSizeArray(config: config)),
            lastBlock: BlockRef.dummy(config: config),
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
                empower: ServiceIdentifier(),
                assign: ServiceIdentifier(),
                designate: ServiceIdentifier()
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
