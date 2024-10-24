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

    @discardableResult
    public func addDevKeys(seed: UInt32) async throws -> KeySet {
        var seedData = Data(repeating: 0, count: 32)
        seedData[0 ..< 4] = seed.encode()
        let seedData32 = Data32(seedData)!
        let bandersnatch = try await add(Bandersnatch.self, seed: seedData32)
        let ed25519 = try await add(Ed25519.self, seed: seedData32)
        let bls = try await add(BLS.self, seed: seedData32)
        return KeySet(bandersnatch: bandersnatch.publicKey, ed25519: ed25519.publicKey, bls: bls.publicKey)
    }

    public static func getDevKey(seed: UInt32) throws -> KeySet {
        var seedData = Data(repeating: 0, count: 32)
        seedData[0 ..< 4] = seed.encode()
        let seedData32 = Data32(seedData)!
        let bandersnatch = try Bandersnatch.SecretKey(from: seedData32)
        let ed25519 = try Ed25519.SecretKey(from: seedData32)
        let bls = try BLS.SecretKey(from: seedData32)
        return KeySet(bandersnatch: bandersnatch.publicKey, ed25519: ed25519.publicKey, bls: bls.publicKey)
    }
}
