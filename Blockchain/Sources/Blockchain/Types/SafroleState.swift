import ScaleCodec
import Utils

public struct SafroleState: Sendable {
    // γk
    public var nextValidators: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    >

    // γz
    public var ticketsVerifierKey: BandersnatchRingVRFRoot

    // γs
    public var ticketsOrKeys: Either<
        ConfigFixedSizeArray<
            Ticket,
            ProtocolConfig.EpochLength
        >,
        ConfigFixedSizeArray<
            BandersnatchPublicKey,
            ProtocolConfig.EpochLength
        >
    >

    // γa
    public var ticketsAccumulator: ConfigLimitedSizeArray<
        Ticket,
        ProtocolConfig.Int0,
        ProtocolConfig.EpochLength
    >

    public init(
        nextValidators: ConfigFixedSizeArray<
            ValidatorKey, ProtocolConfig.TotalNumberOfValidators
        >,
        ticketsVerifierKey: BandersnatchRingVRFRoot,
        ticketsOrKeys: Either<
            ConfigFixedSizeArray<
                Ticket,
                ProtocolConfig.EpochLength
            >,
            ConfigFixedSizeArray<
                BandersnatchPublicKey,
                ProtocolConfig.EpochLength
            >
        >,
        ticketsAccumulator: ConfigLimitedSizeArray<
            Ticket,
            ProtocolConfig.Int0,
            ProtocolConfig.EpochLength
        >
    ) {
        self.nextValidators = nextValidators
        self.ticketsVerifierKey = ticketsVerifierKey
        self.ticketsOrKeys = ticketsOrKeys
        self.ticketsAccumulator = ticketsAccumulator
    }
}

extension SafroleState: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config: Config) -> SafroleState {
        SafroleState(
            nextValidators: ConfigFixedSizeArray(config: config, defaultValue: ValidatorKey.dummy(config: config)),
            ticketsVerifierKey: BandersnatchRingVRFRoot(),
            ticketsOrKeys: .right(ConfigFixedSizeArray(config: config, defaultValue: BandersnatchPublicKey())),
            ticketsAccumulator: ConfigLimitedSizeArray(config: config)
        )
    }
}

extension SafroleState: ScaleCodec.Encodable {
    public init(config: ProtocolConfigRef, from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            nextValidators: ConfigFixedSizeArray(config: config, from: &decoder),
            ticketsVerifierKey: decoder.decode(),
            ticketsOrKeys: Either(
                from: &decoder,
                decodeLeft: { try ConfigFixedSizeArray(config: config, from: &$0) },
                decodeRight: { try ConfigFixedSizeArray(config: config, from: &$0) }
            ),
            ticketsAccumulator: ConfigLimitedSizeArray(config: config, from: &decoder)
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(nextValidators)
        try encoder.encode(ticketsVerifierKey)
        try encoder.encode(ticketsOrKeys)
        try encoder.encode(ticketsAccumulator)
    }
}
