import ScaleCodec
import Utils

public struct EpochMarker: Sendable, Equatable {
    public var entropy: Data32
    public var validators: ConfigFixedSizeArray<
        BandersnatchPublicKey,
        ProtocolConfig.TotalNumberOfValidators
    >

    public init(
        entropy: Data32,
        validators: ConfigFixedSizeArray<
            BandersnatchPublicKey,
            ProtocolConfig.TotalNumberOfValidators
        >
    ) {
        self.entropy = entropy
        self.validators = validators
    }
}

extension EpochMarker: ScaleCodec.Encodable {
    public init(config: ProtocolConfigRef, from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            entropy: decoder.decode(),
            validators: ConfigFixedSizeArray(config: config, from: &decoder)
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(entropy)
        try encoder.encode(validators)
    }
}
