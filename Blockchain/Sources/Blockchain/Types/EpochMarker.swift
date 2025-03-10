import Utils

public struct EpochMarker: Sendable, Equatable, Codable {
    public var entropy: Data32
    public var ticketsEntropy: Data32
    public var validators: ConfigFixedSizeArray<
        BandersnatchPublicKey,
        ProtocolConfig.TotalNumberOfValidators
    >

    public init(
        entropy: Data32,
        ticketsEntropy: Data32,
        validators: ConfigFixedSizeArray<
            BandersnatchPublicKey,
            ProtocolConfig.TotalNumberOfValidators
        >
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
            validators: try! ConfigFixedSizeArray(config: config, defaultValue: Data32())
        )
    }
}
