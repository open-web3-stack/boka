import Utils

public struct EpochMarker: Sendable, Equatable, Codable {
    public struct Keys: Sendable, Equatable, Codable {
        public var bandersnatch: BandersnatchPublicKey
        public var ed25519: Ed25519PublicKey
    }

    public var entropy: Data32
    public var ticketsEntropy: Data32
    public var validators: ConfigLimitedSizeArray<
        Keys,
        ProtocolConfig.MinValidators,
        ProtocolConfig.MaxValidators,
    >

    public init(
        entropy: Data32,
        ticketsEntropy: Data32,
        validators: ConfigLimitedSizeArray<
            Keys,
            ProtocolConfig.MinValidators,
            ProtocolConfig.MaxValidators,
        >,
    ) {
        self.entropy = entropy
        self.ticketsEntropy = ticketsEntropy
        self.validators = validators
    }
}

extension EpochMarker: Dummy {
    public typealias Config = ProtocolConfigRef

    public static func dummy(config: Config) -> EpochMarker {
        EpochMarker(
            entropy: Data32(),
            ticketsEntropy: Data32(),
            validators: try! ConfigLimitedSizeArray(
                config: config,
                array: Array(repeating: Keys(bandersnatch: Data32(), ed25519: Data32()), count: config.value.initialValidatorCount),
            ),
        )
    }
}

extension EpochMarker: Validate {}
