import ScaleCodec
import Utils

public struct ValidatorKey: Sendable, Equatable {
    public var bandersnatch: BandersnatchPublicKey
    public var ed25519: Ed25519PublicKey
    public var bls: BLSKey
    public var metadata: Data128

    public init(
        bandersnatch: BandersnatchPublicKey,
        ed25519: Ed25519PublicKey,
        bls: BLSKey,
        metadata: Data128
    ) {
        self.bandersnatch = bandersnatch
        self.ed25519 = ed25519
        self.bls = bls
        self.metadata = metadata
    }
}

extension ValidatorKey: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config _: Config) -> ValidatorKey {
        ValidatorKey(
            bandersnatch: BandersnatchPublicKey(),
            ed25519: Ed25519PublicKey(),
            bls: BLSKey(),
            metadata: Data128()
        )
    }
}

extension ValidatorKey: ScaleCodec.Codable {
    public init(from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            bandersnatch: decoder.decode(),
            ed25519: decoder.decode(),
            bls: decoder.decode(),
            metadata: decoder.decode()
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(bandersnatch)
        try encoder.encode(ed25519)
        try encoder.encode(bls)
        try encoder.encode(metadata)
    }
}
