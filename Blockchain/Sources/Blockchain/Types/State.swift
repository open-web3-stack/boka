import ScaleCodec
import Utils

public struct State {
    public struct ReportItem {
        public var workReport: WorkReport
        public var guarantors: LimitedSizeArray<Ed25519PublicKey, ConstInt2, ConstInt3>
        public var timestamp: TimeslotIndex

        public init(
            workReport: WorkReport,
            guarantors: LimitedSizeArray<Ed25519PublicKey, ConstInt2, ConstInt3>,
            timestamp: TimeslotIndex
        ) {
            self.workReport = workReport
            self.guarantors = guarantors
            self.timestamp = timestamp
        }
    }

    // α: The core αuthorizations pool.
    public var coreAuthorizationPool: ConfigFixedSizeArray<
        ConfigLimitedSizeArray<
            H256,
            ProtocolConfig.Int0,
            ProtocolConfig.MaxAuthorizationsPoolItems
        >,
        ProtocolConfig.TotalNumberOfCores
    >

    // β: Information on the most recent βlocks.
    public var lastBlock: Block

    // γ: State concerning Safrole.
    public var safroleState: SafroleState

    // δ: The (prior) state of the service accounts.
    public var serviceAccounts: [ServiceIdentifier: ServiceAccount]

    // η: The eηtropy accumulator and epochal raηdomness.
    public var entropyPool: (H256, H256, H256, H256)

    // ι: The validator keys and metadata to be drawn from next.
    public var validatorQueue: FixedSizeArray<
        ValidatorKey, Constants.TotalNumberOfValidators
    >

    // κ: The validator κeys and metadata currently active.
    public var currentValidators: FixedSizeArray<
        ValidatorKey, Constants.TotalNumberOfValidators
    >

    // λ: The validator keys and metadata which were active in the prior epoch.
    public var previousValidators: FixedSizeArray<
        ValidatorKey, Constants.TotalNumberOfValidators
    >

    // ρ: The ρending reports, per core, which are being made available prior to accumulation.
    public var reports: ConfigFixedSizeArray<
        ReportItem?,
        ProtocolConfig.TotalNumberOfCores
    >

    // τ: The most recent block’s τimeslot.
    public var timestamp: TimeslotIndex

    // φ: The authorization queue.
    public var authorizationQueue: ConfigFixedSizeArray<
        FixedSizeArray<
            H256,
            Constants.MaxAuthorizationsQueueItems
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

    public init(
        coreAuthorizationPool: ConfigFixedSizeArray<
            ConfigLimitedSizeArray<
                H256,
                ProtocolConfig.Int0,
                ProtocolConfig.MaxAuthorizationsPoolItems
            >,
            ProtocolConfig.TotalNumberOfCores
        >,
        lastBlock: Block,
        safroleState: SafroleState,
        serviceAccounts: [ServiceIdentifier: ServiceAccount],
        entropyPool: (H256, H256, H256, H256),
        validatorQueue: FixedSizeArray<
            ValidatorKey, Constants.TotalNumberOfValidators
        >,
        currentValidators: FixedSizeArray<
            ValidatorKey, Constants.TotalNumberOfValidators
        >,
        previousValidators: FixedSizeArray<
            ValidatorKey, Constants.TotalNumberOfValidators
        >,
        reports: ConfigFixedSizeArray<
            ReportItem?,
            ProtocolConfig.TotalNumberOfCores
        >,
        timestamp: TimeslotIndex,
        authorizationQueue: ConfigFixedSizeArray<
            FixedSizeArray<
                H256,
                Constants.MaxAuthorizationsQueueItems
            >,
            ProtocolConfig.TotalNumberOfCores
        >,
        privilegedServiceIndices: (
            empower: ServiceIdentifier,
            assign: ServiceIdentifier,
            designate: ServiceIdentifier
        ),
        judgements: JudgementsState
    ) {
        self.coreAuthorizationPool = coreAuthorizationPool
        self.lastBlock = lastBlock
        self.safroleState = safroleState
        self.serviceAccounts = serviceAccounts
        self.entropyPool = entropyPool
        self.validatorQueue = validatorQueue
        self.currentValidators = currentValidators
        self.previousValidators = previousValidators
        self.reports = reports
        self.timestamp = timestamp
        self.authorizationQueue = authorizationQueue
        self.privilegedServiceIndices = privilegedServiceIndices
        self.judgements = judgements
    }
}

public typealias StateRef = Ref<State>

extension State: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(withConfig config: Config) -> State {
        State(
            coreAuthorizationPool: ConfigFixedSizeArray(withConfig: config, defaultValue: ConfigLimitedSizeArray(withConfig: config)),
            lastBlock: Block.dummy(withConfig: config),
            safroleState: SafroleState.dummy(withConfig: config),
            serviceAccounts: [:],
            entropyPool: (H256(), H256(), H256(), H256()),
            validatorQueue: FixedSizeArray(defaultValue: ValidatorKey.dummy(withConfig: config)),
            currentValidators: FixedSizeArray(defaultValue: ValidatorKey.dummy(withConfig: config)),
            previousValidators: FixedSizeArray(defaultValue: ValidatorKey.dummy(withConfig: config)),
            reports: ConfigFixedSizeArray(withConfig: config, defaultValue: nil),
            timestamp: 0,
            authorizationQueue: ConfigFixedSizeArray(withConfig: config, defaultValue: FixedSizeArray(defaultValue: H256())),
            privilegedServiceIndices: (
                empower: ServiceIdentifier(),
                assign: ServiceIdentifier(),
                designate: ServiceIdentifier()
            ),
            judgements: JudgementsState.dummy(withConfig: config)
        )
    }
}

extension State.ReportItem: ScaleCodec.Encodable {
    public init(withConfig config: ProtocolConfigRef, from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            workReport: WorkReport(withConfig: config, from: &decoder),
            guarantors: decoder.decode(),
            timestamp: decoder.decode()
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(workReport)
        try encoder.encode(guarantors)
        try encoder.encode(timestamp)
    }
}

extension State: ScaleCodec.Encodable {
    public init(withConfig config: ProtocolConfigRef, from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            coreAuthorizationPool: ConfigFixedSizeArray(withConfig: config, from: &decoder) {
                try ConfigLimitedSizeArray(withConfig: config, from: &$0) { try $0.decode() }
            },
            lastBlock: Block(withConfig: config, from: &decoder),
            safroleState: SafroleState(withConfig: config, from: &decoder),
            serviceAccounts: decoder.decode(),
            entropyPool: decoder.decode(),
            validatorQueue: decoder.decode(),
            currentValidators: decoder.decode(),
            previousValidators: decoder.decode(),
            reports: ConfigFixedSizeArray(withConfig: config, from: &decoder) { try ReportItem(withConfig: config, from: &$0) },
            timestamp: decoder.decode(),
            authorizationQueue: ConfigFixedSizeArray(withConfig: config, from: &decoder),
            privilegedServiceIndices: decoder.decode(),
            judgements: decoder.decode()
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(coreAuthorizationPool)
        try encoder.encode(lastBlock)
        try encoder.encode(safroleState)
        try encoder.encode(serviceAccounts)
        try encoder.encode(entropyPool)
        try encoder.encode(validatorQueue)
        try encoder.encode(currentValidators)
        try encoder.encode(previousValidators)
        try encoder.encode(reports)
        try encoder.encode(timestamp)
        try encoder.encode(authorizationQueue)
        try encoder.encode(privilegedServiceIndices)
        try encoder.encode(judgements)
    }
}

public extension State {
    func update(with block: Block) -> State {
        let state = State(
            coreAuthorizationPool: coreAuthorizationPool,
            lastBlock: block,
            safroleState: safroleState,
            serviceAccounts: serviceAccounts,
            entropyPool: entropyPool,
            validatorQueue: validatorQueue,
            currentValidators: currentValidators,
            previousValidators: previousValidators,
            reports: reports,
            timestamp: timestamp,
            authorizationQueue: authorizationQueue,
            privilegedServiceIndices: privilegedServiceIndices,
            judgements: judgements
        )
        return state
    }
}
