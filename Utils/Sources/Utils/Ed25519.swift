import Crypto
import Foundation

public struct Ed25519 {
    public let secretKey: Curve25519.Signing.PrivateKey

    public var publicKey: Data32 {
        Data32(secretKey.publicKey.rawRepresentation)!
    }

    public var privateKey: Data32 {
        Data32(secretKey.rawRepresentation)!
    }

    public init() {
        secretKey = Curve25519.Signing.PrivateKey()
    }

    public init?(privateKey: Data32) {
        guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: privateKey.data) else {
            return nil
        }
        secretKey = key
    }

    public func sign(message: Data) throws -> Data64 {
        let signature = try secretKey.signature(for: message)
        return Data64(signature)!
    }

    public func verify(signature: Data64, message: Data, publicKey: Data32) -> Bool {
        guard let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey.data) else {
            return false
        }

        return publicKey.isValidSignature(signature.data, for: message)
    }
}
