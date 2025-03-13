import Foundation
import Testing

@testable import Utils

@Suite struct KeyStoreTests {
    @Test func keyStoreInitialization() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let keyStoreDir = tempDir.appendingPathComponent("KeyStoreTests")
        try? FileManager.default.removeItem(at: keyStoreDir)
        _ = try FilesystemKeyStore(storageDirectory: keyStoreDir)
        #expect(FileManager.default.fileExists(atPath: keyStoreDir.path))
    }

    @Test func generateAndRetrieveKey() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let keyStoreDir = tempDir.appendingPathComponent("KeyStoreTests")
        try? FileManager.default.removeItem(at: keyStoreDir)
        let keyStore = try FilesystemKeyStore(storageDirectory: keyStoreDir)

        let secretKey = try await keyStore.generate(Bandersnatch.self)
        let retrievedKey = await keyStore.get(Bandersnatch.self, publicKey: secretKey.publicKey)
        #expect(retrievedKey != nil)
        #expect(retrievedKey!.publicKey == secretKey.publicKey)
    }

    @Test func addAndRetrieveKey() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let keyStoreDir = tempDir.appendingPathComponent("KeyStoreTests")
        try? FileManager.default.removeItem(at: keyStoreDir)
        let keyStore = try FilesystemKeyStore(storageDirectory: keyStoreDir)

        let seed = Data32.random()
        let secretKey = try await keyStore.add(Bandersnatch.self, seed: seed)
        let retrievedKey = await keyStore.get(Bandersnatch.self, publicKey: secretKey.publicKey)
        #expect(retrievedKey != nil)
        #expect(retrievedKey!.publicKey == secretKey.publicKey)
    }

    @Test func containsKey() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let keyStoreDir = tempDir.appendingPathComponent("KeyStoreTests")
        try? FileManager.default.removeItem(at: keyStoreDir)
        let keyStore = try FilesystemKeyStore(storageDirectory: keyStoreDir)

        let secretKey = try await keyStore.generate(Bandersnatch.self)
        #expect(await keyStore.contains(publicKey: secretKey.publicKey) == true)
    }

    @Test func getAllKeys() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let keyStoreDir = tempDir.appendingPathComponent("KeyStoreTests-\(UUID().uuidString)")
        let keyStore = try FilesystemKeyStore(storageDirectory: keyStoreDir)

        let secretKey1 = try await keyStore.generate(Bandersnatch.self)
        let secretKey2 = try await keyStore.generate(Bandersnatch.self)
        let allKeys = await keyStore.getAll(Bandersnatch.self)
        #expect(allKeys.count == 2)
        #expect(allKeys.contains { $0.publicKey == secretKey1.publicKey })
        #expect(allKeys.contains { $0.publicKey == secretKey2.publicKey })
    }
}
