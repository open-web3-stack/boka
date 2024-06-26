import ScaleCodec
import Utils

public struct SafroleState {
    // γk
    public var pendingValidators: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    >

    // γz
    public var epochRoot: BandersnatchRingVRFRoot

    // γs
    public var slotSealerSeries: Either<
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
    public var ticketAccumulator: ConfigLimitedSizeArray<
        Ticket,
        ProtocolConfig.Int0,
        ProtocolConfig.EpochLength
    >

    public init(
        pendingValidators: ConfigFixedSizeArray<
            ValidatorKey, ProtocolConfig.TotalNumberOfValidators
        >,
        epochRoot: BandersnatchRingVRFRoot,
        slotSealerSeries: Either<
            ConfigFixedSizeArray<
                Ticket,
                ProtocolConfig.EpochLength
            >,
            ConfigFixedSizeArray<
                BandersnatchPublicKey,
                ProtocolConfig.EpochLength
            >
        >,
        ticketAccumulator: ConfigLimitedSizeArray<
            Ticket,
            ProtocolConfig.Int0,
            ProtocolConfig.EpochLength
        >
    ) {
        self.pendingValidators = pendingValidators
        self.epochRoot = epochRoot
        self.slotSealerSeries = slotSealerSeries
        self.ticketAccumulator = ticketAccumulator
    }
}

extension SafroleState: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(withConfig config: Config) -> SafroleState {
        SafroleState(
            pendingValidators: ConfigFixedSizeArray(withConfig: config, defaultValue: ValidatorKey.dummy(withConfig: config)),
            epochRoot: BandersnatchRingVRFRoot(),
            slotSealerSeries: .right(ConfigFixedSizeArray(withConfig: config, defaultValue: BandersnatchPublicKey())),
            ticketAccumulator: ConfigLimitedSizeArray(withConfig: config)
        )
    }
}

extension SafroleState: ScaleCodec.Encodable {
    public init(withConfig config: ProtocolConfigRef, from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            pendingValidators: ConfigFixedSizeArray(withConfig: config, from: &decoder),
            epochRoot: decoder.decode(),
            slotSealerSeries: Either(
                from: &decoder,
                decodeLeft: { try ConfigFixedSizeArray(withConfig: config, from: &$0) },
                decodeRight: { try ConfigFixedSizeArray(withConfig: config, from: &$0) }
            ),
            ticketAccumulator: ConfigLimitedSizeArray(withConfig: config, from: &decoder)
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(pendingValidators)
        try encoder.encode(epochRoot)
        try encoder.encode(slotSealerSeries)
        try encoder.encode(ticketAccumulator)
    }
}
