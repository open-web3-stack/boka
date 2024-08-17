import ScaleCodec
import Utils

public struct SafroleState: Sendable, Equatable {
    // γk
    public var nextValidators: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    >

    // γz
    public var ticketsVerifier: BandersnatchRingVRFRoot

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
        ticketsVerifier: BandersnatchRingVRFRoot,
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
            ticketsAccumulator: ConfigLimitedSizeArray(config: config)
        )
    }
}

extension SafroleState: ScaleCodec.Encodable {
    public init(config: ProtocolConfigRef, from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            nextValidators: ConfigFixedSizeArray(config: config, from: &decoder),
            ticketsVerifier: decoder.decode(),
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
        try encoder.encode(ticketsVerifier)
        try encoder.encode(ticketsOrKeys)
        try encoder.encode(ticketsAccumulator)
    }
}
