import Utils

public struct ValidatorKey {
    public var bandersnatchKey: BandersnatchPublicKey
    public var ed25519Key: Ed25519PublicKey
    public var blsKey: BLSKey
    public var metadata: Data128
}
