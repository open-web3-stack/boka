import Foundation
import Utils

public final class DevKeyStore: KeyStore {
    private let keystore: InMemoryKeyStore

    public init(devKeysCount: Int = 12) async throws {
        keystore = InMemoryKeyStore()
        for i in 0 ..< devKeysCount {
            _ = try await addDevKeys(seed: UInt32(i))
        }
    }

    public func generate<K: KeyType>(_ type: K.Type) async throws -> K.SecretKey {
        try await keystore.generate(type)
    }

    public func add<K: KeyType>(_ type: K.Type, seed: Data32) async throws -> K.SecretKey {
        try await keystore.add(type, seed: seed)
    }

    public func contains(publicKey: some PublicKeyProtocol) async -> Bool {
        await keystore.contains(publicKey: publicKey)
    }

    public func get<K: KeyType>(_ type: K.Type, publicKey: K.SecretKey.PublicKey) async -> K.SecretKey? {
        await keystore.get(type, publicKey: publicKey)
    }

    public func getAll<K: KeyType>(_ type: K.Type) async -> [K.SecretKey] {
        await keystore.getAll(type)
    }

    public static func getDevKey(seed: UInt32) throws -> KeySet {
        let trivialSeed = JIP5SeedDerive.trivialSeed(seed)
        let derivedSeeds = JIP5SeedDerive.deriveKeySeeds(from: trivialSeed)

        let bandersnatch = try Bandersnatch.SecretKey(from: derivedSeeds.bandersnatch)
        let ed25519 = try Ed25519.SecretKey(from: derivedSeeds.ed25519)
        let bls = try BLS.SecretKey(from: trivialSeed)
        return KeySet(bandersnatch: bandersnatch.publicKey, ed25519: ed25519.publicKey, bls: bls.publicKey)
    }
}

extension KeyStore {
    @discardableResult
    public func addDevKeys(seed: UInt32) async throws -> KeySet {
        let trivialSeed = JIP5SeedDerive.trivialSeed(seed)
        return try await generateKeys(from: trivialSeed)
    }
}
