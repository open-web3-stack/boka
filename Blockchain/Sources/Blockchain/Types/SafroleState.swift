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
    public static func dummy(withConfig config: Config) -> SafroleState {
        SafroleState(
            nextValidators: ConfigFixedSizeArray(withConfig: config, defaultValue: ValidatorKey.dummy(withConfig: config)),
            ticketsVerifierKey: BandersnatchRingVRFRoot(),
            ticketsOrKeys: .right(ConfigFixedSizeArray(withConfig: config, defaultValue: BandersnatchPublicKey())),
            ticketsAccumulator: ConfigLimitedSizeArray(withConfig: config)
        )
    }
}

extension SafroleState: ScaleCodec.Encodable {
    public init(withConfig config: ProtocolConfigRef, from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            nextValidators: ConfigFixedSizeArray(withConfig: config, from: &decoder),
            ticketsVerifierKey: decoder.decode(),
            ticketsOrKeys: Either(
                from: &decoder,
                decodeLeft: { try ConfigFixedSizeArray(withConfig: config, from: &$0) },
                decodeRight: { try ConfigFixedSizeArray(withConfig: config, from: &$0) }
            ),
            ticketsAccumulator: ConfigLimitedSizeArray(withConfig: config, from: &decoder)
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(nextValidators)
        try encoder.encode(ticketsVerifierKey)
        try encoder.encode(ticketsOrKeys)
        try encoder.encode(ticketsAccumulator)
    }
}
