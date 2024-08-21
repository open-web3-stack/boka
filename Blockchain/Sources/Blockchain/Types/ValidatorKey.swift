import Utils

public struct ValidatorKey: Sendable, Equatable, Codable {
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
