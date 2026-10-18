import Utils

public struct SafroleState: Sendable, Equatable, Codable {
    /// γk
    public var nextValidators: ValidatorKeys

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
        nextValidators: ValidatorKeys,
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
            nextValidators: ValidatorKeys(config: config, array: Array(repeating: ValidatorKey.dummy(config: config), count: config.value.initialValidatorCount)),
            ticketsVerifier: BandersnatchRingVRFRoot(),
            ticketsOrKeys: .right(ConfigFixedSizeArray(config: config, defaultValue: BandersnatchPublicKey())),
            ticketsAccumulator: ConfigLimitedSizeArray(config: config),
        )
    }
}
