import Foundation

public protocol KeyStore: Sendable {
    func generate<K: KeyType>(_ type: K.Type) async throws -> K.SecretKey
    func add<K: KeyType>(_ type: K.Type, seed: Data32) async throws -> K.SecretKey
    func contains<PK: PublicKeyProtocol>(publicKey: PK) async -> Bool
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
    private let storageDirectory: URL

    public init(storageDirectory: URL) throws {
        self.storageDirectory = storageDirectory
    }

    private func createStorageDirectoryIfNeeded() throws {
        if !FileManager.default.fileExists(atPath: storageDirectory.path) {
            try FileManager.default.createDirectory(
                at: storageDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }

    private func filePath(for publicKey: some PublicKeyProtocol) -> URL {
        let hashableKey = HashableKey(value: publicKey)
        let fileName = "\(hashableKey).json"
        return storageDirectory.appendingPathComponent(fileName)
    }

    private func saveKey(_ key: some SecretKeyProtocol) throws {
        let fileURL = filePath(for: key.publicKey)
        let data = try key.encode()
        try data.write(to: fileURL, options: .atomic)
    }

    private func loadKey<K: KeyType>(_: K.Type, publicKey: K.SecretKey.PublicKey) throws -> K.SecretKey? {
        let fileURL = filePath(for: publicKey)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        return try K.SecretKey.decode(from: data)
    }

    private func deleteKey(for publicKey: some PublicKeyProtocol) throws {
        let fileURL = filePath(for: publicKey)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    public func generate<K: KeyType>(_ type: K.Type) async throws -> K.SecretKey {
        try await add(type, seed: Data32.random())
    }

    public func add<K: KeyType>(_ type: K.Type, seed: Data32) async throws -> K.SecretKey {
        let secretKey = try type.SecretKey(from: seed)
        try saveKey(secretKey)
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
            guard let data = try? Data(contentsOf: fileURL) else { return nil }
            return try? K.SecretKey.decode(from: data)
        }
    }
}
