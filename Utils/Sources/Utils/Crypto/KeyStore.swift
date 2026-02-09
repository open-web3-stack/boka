import Foundation

public protocol KeyStore: Sendable {
    func generate<K: KeyType>(_ type: K.Type) async throws -> K.SecretKey
    func add<K: KeyType>(_ type: K.Type, seed: Data32) async throws -> K.SecretKey
    func contains(publicKey: some PublicKeyProtocol) async -> Bool
    func get<K: KeyType>(_ type: K.Type, publicKey: K.SecretKey.PublicKey) async -> K.SecretKey?
    func getAll<K: KeyType>(_ type: K.Type) async -> [K.SecretKey]
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

    public func getAll<K: KeyType>(_: K.Type) async -> [K.SecretKey] {
        keys.compactMap { _, value in
            value as? K.SecretKey
        }
    }
}

public actor FilesystemKeyStore: KeyStore {
    public enum Error: Swift.Error {
        case invalidSeed
        case invalidPublicKey
    }

    struct KeyData: Codable {
        let publicKey: String
        let seed: String
    }

    private let storageDirectory: URL

    public init(storageDirectory: URL) throws {
        self.storageDirectory = storageDirectory
        if !FileManager.default.fileExists(atPath: storageDirectory.path) {
            try FileManager.default.createDirectory(
                at: self.storageDirectory,
                withIntermediateDirectories: true,
                attributes: nil,
            )
        }
    }

    func filePath(for publicKey: some PublicKeyProtocol) -> URL {
        storageDirectory.appendingPathComponent("\(publicKey.toHexString()).json")
    }

    private func saveKey(_ key: some SecretKeyProtocol, seed: Data32) throws {
        let fileURL = filePath(for: key.publicKey)
        let keyData = KeyData(publicKey: key.publicKey.toHexString(), seed: seed.data.toHexString())
        try JSONEncoder().encode(keyData).write(to: fileURL, options: .atomic)
    }

    private func loadKey<K: KeyType>(_: K.Type, publicKey: K.SecretKey.PublicKey) throws -> K.SecretKey? {
        let fileURL = filePath(for: publicKey)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let jsonData = try Data(contentsOf: fileURL)
        let keyData = try JSONDecoder().decode(KeyData.self, from: jsonData)
        if publicKey.toHexString() != keyData.publicKey {
            throw Error.invalidPublicKey
        }
        guard let seed = Data32(fromHexString: keyData.seed) else {
            throw Error.invalidSeed
        }
        return try K.SecretKey(from: seed)
    }

    public func generate<K: KeyType>(_ type: K.Type) async throws -> K.SecretKey {
        try await add(type, seed: Data32.random())
    }

    public func add<K: KeyType>(_ type: K.Type, seed: Data32) async throws -> K.SecretKey {
        let secretKey = try type.SecretKey(from: seed)
        try saveKey(secretKey, seed: seed)
        return secretKey
    }

    public func contains(publicKey: some PublicKeyProtocol) async -> Bool {
        let fileURL = filePath(for: publicKey)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    public func get<K: KeyType>(_ type: K.Type, publicKey: K.SecretKey.PublicKey) async -> K.SecretKey? {
        try? loadKey(type, publicKey: publicKey)
    }

    public func getAll<K: KeyType>(_: K.Type) async -> [K.SecretKey] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil) else {
            return []
        }

        return files.compactMap { fileURL in
            guard let jsonData = try? Data(contentsOf: fileURL),
                  let keyData = try? JSONDecoder().decode(KeyData.self, from: jsonData),
                  let seed = Data32(fromHexString: keyData.seed),
                  let secretKey = try? K.SecretKey(from: seed),
                  secretKey.publicKey.toHexString() == keyData.publicKey
            else {
                return nil
            }
            return secretKey
        }
    }
}
