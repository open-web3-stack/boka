import Foundation
import Testing

@testable import Utils

@Suite struct Ed25519Tests {
    @Test func validateSignature() throws {
        let secretKey = try Ed25519.SecretKey(from: Data32.random())
        let publicKey = secretKey.publicKey

        let message = Data("test".utf8)
        let signature = try secretKey.sign(message: message)

        #expect(publicKey.verify(signature: signature, message: message))
    }

    @Test func rejectInvalidMessage() throws {
        let secretKey = try Ed25519.SecretKey(from: Data32.random())
        let publicKey = secretKey.publicKey

        let message = Data("test".utf8)
        let signature = try secretKey.sign(message: message)
        let invalidMessage = Data("tests".utf8)

        #expect(!publicKey.verify(signature: signature, message: invalidMessage))
    }

    @Test func rejectTamperedSignature() throws {
        let secretKey = try Ed25519.SecretKey(from: Data32.random())
        let publicKey = secretKey.publicKey

        let message = Data("test".utf8)
        let signature = try secretKey.sign(message: message)

        var tamperedSignature = signature.data
        tamperedSignature.replaceSubrange(0 ... 1, with: [10, 12])

        #expect(!publicKey.verify(signature: Data64(tamperedSignature)!, message: message))
    }

    @Test func initializeFromData() throws {
        let secretKey = try Ed25519.SecretKey(from: Data32.random())
        let publicKey = secretKey.publicKey
        let publicKeyData = publicKey.data

        // Re-create from the same data
        let recreatedKey = try Ed25519.PublicKey(from: publicKeyData)
        #expect(recreatedKey.data == publicKeyData)
    }

    @Test func encodeAndDecode() throws {
        let secretKey = try Ed25519.SecretKey(from: Data32.random())
        let originalKey = secretKey.publicKey

        let encoder = JSONEncoder()
        let encodedData = try encoder.encode(originalKey)

        let decoder = JSONDecoder()
        let decodedKey = try decoder.decode(Ed25519.PublicKey.self, from: encodedData)

        #expect(decodedKey == originalKey)
    }

    @Test func hashAndEquality() throws {
        let secretKey1 = try Ed25519.SecretKey(from: Data32.random())
        let secretKey2 = try Ed25519.SecretKey(from: Data32.random())

        let publicKey1 = secretKey1.publicKey
        let publicKey2 = try Ed25519.PublicKey(from: publicKey1.data) // Same key from data
        let publicKey3 = secretKey2.publicKey // Different key

        var hashSet: Set<Ed25519.PublicKey> = []
        hashSet.insert(publicKey1)

        #expect(publicKey1 == publicKey2)
        #expect(publicKey1 != publicKey3)
        #expect(hashSet.contains(publicKey2))
        #expect(!hashSet.contains(publicKey3))
    }

    @Test func descriptionCheck() throws {
        let secretKey = try Ed25519.SecretKey(from: Data32.random())
        let publicKey = secretKey.publicKey
        let publicKeyData = publicKey.data

        #expect(publicKey.description == publicKeyData.description)
    }

    @Test func signatureVerification() throws {
        let secretKey = try Ed25519.SecretKey(from: Data32.random())
        let publicKey = secretKey.publicKey

        let message = Data("test message".utf8)
        let signature = try secretKey.sign(message: message)

        #expect(publicKey.verify(signature: signature, message: message))

        let invalidMessage = Data("tampered message".utf8)
        #expect(!publicKey.verify(signature: signature, message: invalidMessage))

        var tamperedSignature = signature.data
        tamperedSignature[0] ^= 0xFF
        #expect(!publicKey.verify(signature: Data64(tamperedSignature)!, message: message))
    }
}
