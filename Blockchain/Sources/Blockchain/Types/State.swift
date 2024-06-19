import Utils

public struct State {
    // α: The core αuthorizations pool.
    public var coreAuthorizationPool: FixedSizeArray<
        LimitedSizeArray<
            H256,
            ConstInt0,
            Constants.MaxAuthorizationsPoolItems
        >,
        Constants.TotalNumberOfCores
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
    public var reports: FixedSizeArray<
        (
            workReport: WorkReport,
            guarantors: LimitedSizeArray<
                Ed25519PublicKey,
                ConstInt2,
                ConstInt3
            >,
            timestamp: TimeslotIndex
        )?,
        Constants.TotalNumberOfCores
    >

    // τ: The most recent block’s τimeslot.
    public var timestamp: TimeslotIndex

    // φ: The authorization queue.
    public var authorizationQueue: FixedSizeArray<
        FixedSizeArray<
            H256,
            Constants.MaxAuthorizationsQueueItems
        >,
        Constants.TotalNumberOfCores
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
        coreAuthorizationPool: FixedSizeArray<
            LimitedSizeArray<
                H256,
                ConstInt0,
                Constants.MaxAuthorizationsPoolItems
            >,
            Constants.TotalNumberOfCores
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
        reports: FixedSizeArray<
            (
                workReport: WorkReport,
                guarantors: LimitedSizeArray<
                    Ed25519PublicKey,
                    ConstInt2,
                    ConstInt3
                >,
                timestamp: TimeslotIndex
            )?,
            Constants.TotalNumberOfCores
        >,
        timestamp: TimeslotIndex,
        authorizationQueue: FixedSizeArray<
            FixedSizeArray<
                H256,
                Constants.MaxAuthorizationsQueueItems
            >,
            Constants.TotalNumberOfCores
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
    public static var dummy: State {
        State(
            coreAuthorizationPool: FixedSizeArray(defaultValue: []),
            lastBlock: Block.dummy,
            safroleState: SafroleState.dummy,
            serviceAccounts: [:],
            entropyPool: (H256(), H256(), H256(), H256()),
            validatorQueue: FixedSizeArray(defaultValue: ValidatorKey.dummy),
            currentValidators: FixedSizeArray(defaultValue: ValidatorKey.dummy),
            previousValidators: FixedSizeArray(defaultValue: ValidatorKey.dummy),
            reports: FixedSizeArray(defaultValue: nil),
            timestamp: 0,
            authorizationQueue: FixedSizeArray(defaultValue: FixedSizeArray(defaultValue: H256())),
            privilegedServiceIndices: (
                empower: ServiceIdentifier(),
                assign: ServiceIdentifier(),
                designate: ServiceIdentifier()
            ),
            judgements: JudgementsState.dummy
        )
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
