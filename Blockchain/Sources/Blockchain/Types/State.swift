import Utils

public struct State {
    // α: The core αuthorizations pool.
    public private(set) var coreAuthorizationPool: FixedSizeArray<
        LimitedSizeArray<
            H256,
            ConstInt0,
            Constants.MaxAuthorizationsPoolItems
        >,
        Constants.TotalNumberOfCores
    >

    // β: Information on the most recent βlocks.
    public private(set) var lastBlock: Block

    // γ: State concerning Safrole.
    public private(set) var safroleState: SafroleState

    // δ: The (prior) state of the service accounts.
    public private(set) var serviceAccounts: [ServiceIdentifier: ServiceAccount]

    // η: The eηtropy accumulator and epochal raηdomness.
    public private(set) var entropyPool: (H256, H256, H256, H256)

    // ι: The validator keys and metadata to be drawn from next.
    public private(set) var validatorQueue: FixedSizeArray<
        ValidatorKey, Constants.TotalNumberOfValidators
    >

    // κ: The validator κeys and metadata currently active.
    public private(set) var currentValidators: FixedSizeArray<
        ValidatorKey, Constants.TotalNumberOfValidators
    >

    // λ: The validator keys and metadata which were active in the prior epoch.
    public private(set) var previousValidators: FixedSizeArray<
        ValidatorKey, Constants.TotalNumberOfValidators
    >

    // ρ: The ρending reports, per core, which are being made available prior to accumulation.
    public private(set) var reports: FixedSizeArray<
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
    public private(set) var timestamp: TimeslotIndex

    // φ: The authorization queue.
    public private(set) var authorizationQueue: FixedSizeArray<
        FixedSizeArray<
            H256,
            Constants.MaxAuthorizationsQueueItems
        >,
        Constants.TotalNumberOfCores
    >

    // χ: The privileged service indices.
    public private(set) var privilegedServiceIndices: (
        empower: ServiceIdentifier,
        assign: ServiceIdentifier,
        designate: ServiceIdentifier
    )

    // ψ: past judgements
    public private(set) var judgements: JudgementsState
}

public typealias StateRef = Ref<State>
