import Utils

public struct SafroleState: Sendable, Equatable, Codable {
    /// γk
    public var nextValidators: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators,
    >

    /// γz
    public var ticketsVerifier: BandersnatchRingVRFRoot

    /// γs
    public var ticketsOrKeys: SafroleTicketsOrKeys

    /// γa
    public var ticketsAccumulator: ConfigLimitedSizeArray<
        Ticket,
        ProtocolConfig.Int0,
        ProtocolConfig.EpochLength,
    >

    public init(
        nextValidators: ConfigFixedSizeArray<
            ValidatorKey, ProtocolConfig.TotalNumberOfValidators,
        >,
        ticketsVerifier: BandersnatchRingVRFRoot,
        ticketsOrKeys: SafroleTicketsOrKeys,
        ticketsAccumulator: ConfigLimitedSizeArray<
            Ticket,
            ProtocolConfig.Int0,
            ProtocolConfig.EpochLength,
        >,
    ) {
        self.nextValidators = nextValidators
        self.ticketsVerifier = ticketsVerifier
        self.ticketsOrKeys = ticketsOrKeys
        self.ticketsAccumulator = ticketsAccumulator
    }
}

extension SafroleState: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config: Config) -> SafroleState {
        try! SafroleState(
            nextValidators: ConfigFixedSizeArray(config: config, defaultValue: ValidatorKey.dummy(config: config)),
            ticketsVerifier: BandersnatchRingVRFRoot(),
            ticketsOrKeys: .right(ConfigFixedSizeArray(config: config, defaultValue: BandersnatchPublicKey())),
            ticketsAccumulator: ConfigLimitedSizeArray(config: config),
        )
    }
}
