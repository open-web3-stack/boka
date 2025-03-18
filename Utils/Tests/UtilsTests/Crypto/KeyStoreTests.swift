import Foundation
import Testing

@testable import Utils

final class KeyStoreTests {
    let keyStoreDir: URL

    init() {
        let random = UUID().uuidString
        keyStoreDir = FileManager.default.temporaryDirectory.appendingPathComponent(random)
    }

    deinit {
        try? FileManager.default.removeItem(at: keyStoreDir)
    }

    @Test func keyStoreInitialization() throws {
        _ = try FilesystemKeyStore(storageDirectory: keyStoreDir)
        #expect(FileManager.default.fileExists(atPath: keyStoreDir.path))
    }

    @Test func generateAndRetrieveKey() async throws {
        let keyStore = try FilesystemKeyStore(storageDirectory: keyStoreDir)
        let secretKey = try await keyStore.generate(Bandersnatch.self)
        let retrievedKey = try #require(await keyStore.get(Bandersnatch.self, publicKey: secretKey.publicKey))
        #expect(retrievedKey.publicKey == secretKey.publicKey)
    }

    @Test func addAndRetrieveKey() async throws {
        let keyStore = try FilesystemKeyStore(storageDirectory: keyStoreDir)

        let seed = Data32.random()
        let secretKey = try await keyStore.add(Bandersnatch.self, seed: seed)
        let retrievedKey = await keyStore.get(Bandersnatch.self, publicKey: secretKey.publicKey)
        #expect(retrievedKey != nil)
        #expect(retrievedKey!.publicKey == secretKey.publicKey)

        let randomSecretKey = try await InMemoryKeyStore().add(Bandersnatch.self, seed: Data32.random())
        let retrievedRandomKey = await keyStore.get(Bandersnatch.self, publicKey: randomSecretKey.publicKey)
        #expect(retrievedRandomKey == nil)

        let path = await keyStore.filePath(for: secretKey.publicKey)
        try Data(repeating: 0, count: 20).write(to: path, options: .atomic)
        let emptyKey = await keyStore.get(Bandersnatch.self, publicKey: secretKey.publicKey)
        #expect(emptyKey == nil)
    }

    @Test func containsKey() async throws {
        let keyStore = try FilesystemKeyStore(storageDirectory: keyStoreDir)

        let secretKey = try await keyStore.generate(Bandersnatch.self)
        #expect(await keyStore.contains(publicKey: secretKey.publicKey) == true)
    }

    @Test func getAllKeys() async throws {
        let keyStore = try FilesystemKeyStore(storageDirectory: keyStoreDir)
        let allKeysCount = await keyStore.getAll(Bandersnatch.self).count
        #expect(allKeysCount == 0)

        let secretKey1 = try await keyStore.generate(Bandersnatch.self)
        let secretKey2 = try await keyStore.generate(Bandersnatch.self)
        let allKeys = await keyStore.getAll(Bandersnatch.self)
        #expect(allKeys.count == 2)
        #expect(allKeys.contains { $0.publicKey == secretKey1.publicKey })
        #expect(allKeys.contains { $0.publicKey == secretKey2.publicKey })
    }
}
