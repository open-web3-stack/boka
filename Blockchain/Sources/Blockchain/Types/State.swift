import Utils

public struct State {
    // α: The core αuthorizations pool.
    public private(set) var coreAuthorizationPool: SizeLimitedArray<
        SizeLimitedArray<
            H256, Constants.Zero, Constants.MaxAuthorizationsPoolItems
        >,
        Constants.TotalNumberOfCores,
        Constants.TotalNumberOfCores
    >

    // β: Information on the most recent βlocks.
    public private(set) var lastBlock: Block

    // γ: State concerning Safrole.
    public private(set) var safroleState: SafroleState

    // δ: The (prior) state of the service accounts.
    public private(set) var serviceAccounts: [ServiceIdentifier: ServiceAccount]

    // η: The eηtropy accumulator and epochal raηdomness.
    public private(set) var entropyPool: () // TODO: figure out the type

    // ι: The validator keys and metadata to be drawn from next.
    public private(set) var validatorQueue: () // TODO: figure out the type

    // κ: The validator κeys and metadata currently active.
    public private(set) var currentValidators: () // TODO: figure out the type

    // λ: The validator keys and metadata which were active in the prior epoch.
    public private(set) var previousValidators: () // TODO: figure out the type

    // ρ: The ρending reports, per core, which are being made available prior to accumulation.
    public private(set) var reports: () // TODO: figure out the type

    // τ: The most recent block’s τimeslot.
    public private(set) var timestamp: TimeslotIndex

    // φ: The authorization queue.
    public private(set) var authorizationQueue: () // TODO: figure out the type

    // ψ: Votes regarding any ongoing disputes.
    public private(set) var disputes: () // TODO: figure out the type

    // χ: The privileged service indices.
    public private(set) var privilegedServiceIndices: () // TODO: figure out the type
}

public typealias StateRef = Ref<State>
