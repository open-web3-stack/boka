import Crypto
import Foundation

public enum Ed25519: KeyType {
    public final class SecretKey: SecretKeyProtocol {
        private let secretKey: Curve25519.Signing.PrivateKey
        public let publicKey: PublicKey

        public init(from seed: Data32) throws {
            secretKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed.data)
            publicKey = PublicKey(pk: secretKey.publicKey)
        }

        public func sign(message: Data) throws -> Data64 {
            let signature = try secretKey.signature(for: message)
            return Data64(signature)!
        }
    }

    public final class PublicKey: PublicKeyProtocol {
        private let publicKey: Curve25519.Signing.PublicKey
        public let data: Data32

        fileprivate init(pk: Curve25519.Signing.PublicKey) {
            publicKey = pk
            data = Data32(pk.rawRepresentation)!
        }

        public init(from data: Data32) throws {
            publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: data.data)
            self.data = data
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(data)
        }

        public convenience init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let data = try container.decode(Data32.self)
            try self.init(from: data)
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(data)
        }

        public static func == (lhs: PublicKey, rhs: PublicKey) -> Bool {
            lhs.data == rhs.data
        }

        public func verify(signature: Data64, message: Data) -> Bool {
            publicKey.isValidSignature(signature.data, for: message)
        }
    }
}
