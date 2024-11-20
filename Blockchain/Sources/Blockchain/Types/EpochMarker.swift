import Utils

public struct EpochMarker: Sendable, Equatable, Codable {
    public var entropyOne: Data32
    public var entropyTwo: Data32
    public var validators: ConfigFixedSizeArray<
        BandersnatchPublicKey,
        ProtocolConfig.TotalNumberOfValidators
    >

    public init(
        entropyOne: Data32,
        entropyTwo: Data32,
        validators: ConfigFixedSizeArray<
            BandersnatchPublicKey,
            ProtocolConfig.TotalNumberOfValidators
        >
    ) {
        self.entropyOne = entropyOne
        self.entropyTwo = entropyTwo
        self.validators = validators
    }
}
