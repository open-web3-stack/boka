import Foundation

public protocol KeyStore: Sendable {
    func generate<K: KeyType>(_ type: K.Type) async throws -> K.SecretKey
    func add<K: KeyType>(_ type: K.Type, seed: Data32) async throws -> K.SecretKey
    func contains<PK: PublicKeyProtocol>(publicKey: PK) async -> Bool
    func get<K: KeyType>(_ type: K.Type, publicKey: K.SecretKey.PublicKey) async -> K.SecretKey?
}

struct HashableKey: Hashable {
    let value: any PublicKeyProtocol

    func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }

    static func == (lhs: HashableKey, rhs: HashableKey) -> Bool {
        lhs.value.equals(rhs: rhs.value)
    }
}

public actor InMemoryKeyStore: KeyStore {
    private var keys: [HashableKey: any SecretKeyProtocol] = [:]

    public init() {}

    public func generate<K: KeyType>(_ type: K.Type) async throws -> K.SecretKey {
        try await add(type, seed: Data32.random())
    }

    public func add<K: KeyType>(_ type: K.Type, seed: Data32) async throws -> K.SecretKey {
        let secretKey = try type.SecretKey(from: seed)
        let hashableKey = HashableKey(value: secretKey.publicKey)
        keys[hashableKey] = secretKey
        return secretKey
    }

    public func contains(publicKey: some PublicKeyProtocol) async -> Bool {
        let hashableKey = HashableKey(value: publicKey)
        return keys[hashableKey] != nil
    }

    public func get<K: KeyType>(_: K.Type, publicKey: K.SecretKey.PublicKey) async -> K.SecretKey? {
        let hashableKey = HashableKey(value: publicKey)
        return keys[hashableKey] as? K.SecretKey
    }
}
