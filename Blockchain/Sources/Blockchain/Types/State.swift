import ScaleCodec
import Utils

public struct State: Sendable {
    public struct ReportItem: Sendable, Equatable {
        public var workReport: WorkReport
        public var guarantors: LimitedSizeArray<Ed25519PublicKey, ConstInt2, ConstInt3>
        public var timeslot: TimeslotIndex

        public init(
            workReport: WorkReport,
            guarantors: LimitedSizeArray<Ed25519PublicKey, ConstInt2, ConstInt3>,
            timeslot: TimeslotIndex
        ) {
            self.workReport = workReport
            self.guarantors = guarantors
            self.timeslot = timeslot
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
    public var entropyPool: (Data32, Data32, Data32, Data32)

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
    public var privilegedServiceIndices: (
        empower: ServiceIdentifier,
        assign: ServiceIdentifier,
        designate: ServiceIdentifier
    )

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
        entropyPool: (Data32, Data32, Data32, Data32),
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
        privilegedServiceIndices: (
            empower: ServiceIdentifier,
            assign: ServiceIdentifier,
            designate: ServiceIdentifier
        ),
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
            entropyPool: (Data32(), Data32(), Data32(), Data32()),
            validatorQueue: ConfigFixedSizeArray(config: config, defaultValue: ValidatorKey.dummy(config: config)),
            currentValidators: ConfigFixedSizeArray(config: config, defaultValue: ValidatorKey.dummy(config: config)),
            previousValidators: ConfigFixedSizeArray(config: config, defaultValue: ValidatorKey.dummy(config: config)),
            reports: ConfigFixedSizeArray(config: config, defaultValue: nil),
            timeslot: 0,
            authorizationQueue: ConfigFixedSizeArray(
                config: config,
                defaultValue: ConfigFixedSizeArray(config: config, defaultValue: Data32())
            ),
            privilegedServiceIndices: (
                empower: ServiceIdentifier(),
                assign: ServiceIdentifier(),
                designate: ServiceIdentifier()
            ),
            judgements: JudgementsState.dummy(config: config),
            activityStatistics: ValidatorActivityStatistics.dummy(config: config)
        )
    }
}

extension State.ReportItem: ScaleCodec.Encodable {
    public init(config: ProtocolConfigRef, from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            workReport: WorkReport(config: config, from: &decoder),
            guarantors: decoder.decode(),
            timeslot: decoder.decode()
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(workReport)
        try encoder.encode(guarantors)
        try encoder.encode(timeslot)
    }
}

extension State: ScaleCodec.Encodable {
    public init(config: ProtocolConfigRef, from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            config: config,
            coreAuthorizationPool: ConfigFixedSizeArray(config: config, from: &decoder) {
                try ConfigLimitedSizeArray(config: config, from: &$0) { try $0.decode() }
            },
            lastBlock: Block(config: config, from: &decoder).asRef(),
            safroleState: SafroleState(config: config, from: &decoder),
            serviceAccounts: decoder.decode(),
            entropyPool: decoder.decode(),
            validatorQueue: ConfigFixedSizeArray(config: config, from: &decoder),
            currentValidators: ConfigFixedSizeArray(config: config, from: &decoder),
            previousValidators: ConfigFixedSizeArray(config: config, from: &decoder),
            reports: ConfigFixedSizeArray(config: config, from: &decoder) { try ReportItem(config: config, from: &$0) },
            timeslot: decoder.decode(),
            authorizationQueue: ConfigFixedSizeArray(config: config, from: &decoder) {
                try ConfigFixedSizeArray(config: config, from: &$0)
            },
            privilegedServiceIndices: decoder.decode(),
            judgements: decoder.decode(),
            activityStatistics: ValidatorActivityStatistics(config: config, from: &decoder)
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(coreAuthorizationPool)
        try encoder.encode(lastBlock.value)
        try encoder.encode(safroleState)
        try encoder.encode(serviceAccounts)
        try encoder.encode(entropyPool)
        try encoder.encode(validatorQueue)
        try encoder.encode(currentValidators)
        try encoder.encode(previousValidators)
        try encoder.encode(reports)
        try encoder.encode(timeslot)
        try encoder.encode(authorizationQueue)
        try encoder.encode(privilegedServiceIndices)
        try encoder.encode(judgements)
        try encoder.encode(activityStatistics)
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
