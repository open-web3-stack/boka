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
        let randomData = Data32.random()
        let publicKey = try Ed25519.PublicKey(from: randomData)
        #expect(publicKey.data == randomData)
    }

    @Test func encodeAndDecode() throws {
        let originalData = Data32.random()
        let originalKey = try Ed25519.PublicKey(from: originalData)

        let encoder = JSONEncoder()
        let encodedData = try encoder.encode(originalKey)

        let decoder = JSONDecoder()
        let decodedKey = try decoder.decode(Ed25519.PublicKey.self, from: encodedData)

        #expect(decodedKey == originalKey)
    }

    @Test func hashAndEquality() throws {
        let data1 = Data32.random()
        let data2 = Data32.random()

        let publicKey1 = try Ed25519.PublicKey(from: data1)
        let publicKey2 = try Ed25519.PublicKey(from: data1)
        let publicKey3 = try Ed25519.PublicKey(from: data2)

        var hashSet: Set<Ed25519.PublicKey> = []
        hashSet.insert(publicKey1)

        #expect(publicKey1 == publicKey2)
        #expect(publicKey1 != publicKey3)
        #expect(hashSet.contains(publicKey2))
        #expect(!hashSet.contains(publicKey3))
    }

    @Test func descriptionCheck() throws {
        let randomData = Data32.random()
        let publicKey = try Ed25519.PublicKey(from: randomData)

        #expect(publicKey.description == randomData.description)
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
