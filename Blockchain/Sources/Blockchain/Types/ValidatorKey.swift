import Foundation
import Utils

public struct ValidatorKey: Sendable, Equatable, Codable, Hashable {
    public enum Error: Swift.Error {
        case invalidDataLength
    }

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

    public init(data: Data) throws {
        guard data.count == 336 else {
            throw Error.invalidDataLength
        }
        bandersnatch = BandersnatchPublicKey(data[0 ..< 32])!
        ed25519 = Ed25519PublicKey(data[32 ..< 64])!
        bls = BLSKey(data[64 ..< 64 + 144])!
        metadata = Data128(data[208 ..< 208 + 128])!
    }

    public init() {
        bandersnatch = BandersnatchPublicKey()
        ed25519 = Ed25519PublicKey()
        bls = BLSKey()
        metadata = Data128()
    }

    public var metadataString: String {
        // we want this behaviour rather than fail on invalid utf8
        // swiftlint:disable optional_data_string_conversion
        String(decoding: metadata.data, as: UTF8.self)
        // swiftlint:enable optional_data_string_conversion
    }
}

extension ValidatorKey: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config _: Config) -> ValidatorKey {
        ValidatorKey()
    }
}
