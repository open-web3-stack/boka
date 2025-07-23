import Foundation
import Utils

public struct KeySet: Codable, Sendable {
    public let bandersnatch: Bandersnatch.PublicKey
    public let ed25519: Ed25519.PublicKey
    public let bls: BLS.PublicKey

    public init(bandersnatch: Bandersnatch.PublicKey, ed25519: Ed25519.PublicKey, bls: BLS.PublicKey) {
        self.bandersnatch = bandersnatch
        self.ed25519 = ed25519
        self.bls = bls
    }
}

extension KeyStore {
    public func generateKeys(from seed: Data32) async throws -> KeySet {
        let derivedSeeds = JIP5SeedDerive.deriveKeySeeds(from: seed)

        let bandersnatch = try await add(Bandersnatch.self, seed: derivedSeeds.bandersnatch)
        let ed25519 = try await add(Ed25519.self, seed: derivedSeeds.ed25519)
        let bls = try await add(BLS.self, seed: seed)

        return KeySet(bandersnatch: bandersnatch.publicKey, ed25519: ed25519.publicKey, bls: bls.publicKey)
    }

    public func addKeys(bandersnatch: Data32, ed25519: Data32, bls: Data32) async throws -> KeySet {
        let bandersnatch = try await add(Bandersnatch.self, seed: bandersnatch)
        let ed25519 = try await add(Ed25519.self, seed: ed25519)
        let bls = try await add(BLS.self, seed: bls)
        return KeySet(bandersnatch: bandersnatch.publicKey, ed25519: ed25519.publicKey, bls: bls.publicKey)
    }
}
