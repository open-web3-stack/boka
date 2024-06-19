import Utils

public struct ValidatorKey {
    public var bandersnatchKey: BandersnatchPublicKey
    public var ed25519Key: Ed25519PublicKey
    public var blsKey: BLSKey
    public var metadata: Data128

    public init(
        bandersnatchKey: BandersnatchPublicKey,
        ed25519Key: Ed25519PublicKey,
        blsKey: BLSKey,
        metadata: Data128
    ) {
        self.bandersnatchKey = bandersnatchKey
        self.ed25519Key = ed25519Key
        self.blsKey = blsKey
        self.metadata = metadata
    }
}

extension ValidatorKey: Dummy {
    public static var dummy: ValidatorKey {
        ValidatorKey(
            bandersnatchKey: BandersnatchPublicKey(),
            ed25519Key: Ed25519PublicKey(),
            blsKey: BLSKey(),
            metadata: Data128()
        )
    }
}
