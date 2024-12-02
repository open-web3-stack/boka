import bls
import Foundation
import Testing

@testable import Utils

@Suite struct BLSTests {
    @Test func BLSSignatureWorks() throws {
        let bls = try BLS.SecretKey(from: Data32())
        let publicKey1 = bls.publicKey
        #expect(publicKey1.data.data.count == Int(BLS_PUBLICKEY_SERIALIZED_SIZE))
        let message1 = Data("test1".utf8)
        let signature1 = try bls.sign(message: message1)
        #expect(signature1.count == Int(BLS_SIGNATURE_SERIALIZED_SIZE))

        #expect(
            try publicKey1.verify(signature: signature1, message: message1)
        )

        let invalidMessage = Data("testUnknown".utf8)
        #expect(
            try !publicKey1.verify(signature: signature1, message: invalidMessage)
        )

        var invalidSignature = signature1
        invalidSignature.replaceSubrange(0 ... 1, with: [2, 3])
        #expect(
            try !publicKey1.verify(signature: invalidSignature, message: message1)
        )

        let bls2 = try BLS.SecretKey(from: Data32.random())
        let publicKey2 = bls2.publicKey
        let message2 = Data("test2".utf8)
        let signature2 = try bls2.sign(message: message2)

        #expect(
            try publicKey2.verify(signature: signature2, message: message2)
        )

        #expect(
            try BLS.aggregateVerify(
                message: message1,
                signatures: [signature1],
                publicKeys: [publicKey1]
            )
        )

        #expect(
            try !BLS.aggregateVerify(
                message: message2,
                signatures: [signature1],
                publicKeys: [publicKey1]
            )
        )

        let bls3 = try BLS.SecretKey(from: Data32.random())
        let publicKey3 = bls3.publicKey
        let signature3 = try bls3.sign(message: message1)

        #expect(
            try BLS.aggregateVerify(
                message: message1,
                signatures: [signature1, signature3],
                publicKeys: [publicKey1, publicKey3]
            )
        )
    }

    @Test func BLSKeyInitialization() throws {
        let seed = Data32.random()
        let bls = try BLS.SecretKey(from: seed)
        #expect(bls.publicKey.data.data.count == Int(BLS_PUBLICKEY_SERIALIZED_SIZE))
    }

    @Test func BLSSignatureSizeValidation() throws {
        let bls = try BLS.SecretKey(from: Data32.random())
        let message = Data("test".utf8)
        let signature = try bls.sign(message: message)
        #expect(signature.count == Int(BLS_SIGNATURE_SERIALIZED_SIZE))
    }

    @Test func BLSPublicKeySerialization() throws {
        let bls = try BLS.SecretKey(from: Data32.random())
        let publicKey = bls.publicKey

        // Encode and decode the public key
        let encoder = JSONEncoder()
        let encodedData = try encoder.encode(publicKey)
        let decoder = JSONDecoder()
        let decodedPublicKey = try decoder.decode(BLS.PublicKey.self, from: encodedData)

        #expect(decodedPublicKey == publicKey)
    }

    @Test func BLSPublicKeyEquality() throws {
        let key1 = try BLS.SecretKey(from: Data32.random()).publicKey
        let key2 = try BLS.SecretKey(from: Data32.random()).publicKey
        #expect(key1 != key2)
    }

    @Test func PublicKeySerialization() throws {
        let key1 = try BLS.SecretKey(from: Data32.random()).publicKey.data
        let publicKey = try BLS.PublicKey(data: key1)

        // Test encoding and decoding
        let encoder = JSONEncoder()
        let encoded = try encoder.encode(publicKey)

        let decoder = JSONDecoder()
        let decodedPublicKey = try decoder.decode(BLS.PublicKey.self, from: encoded)

        #expect(publicKey == decodedPublicKey)
        #expect(publicKey.description == decodedPublicKey.description)
    }

    @Test func PublicKey() throws {
        let keyData1 = Data144.random()
        #expect(throws: Error.self) {
            _ = try BLS.PublicKey(data: keyData1)
        }
    }

    @Test func PublicKeyVerifyValidSignature() throws {
        let bls = try BLS.SecretKey(from: Data32.random())
        let publicKey = bls.publicKey
        let message = Data("testMessage".utf8)
        let signature = try bls.sign(message: message)

        // Test valid signature verification
        #expect(try publicKey.verify(signature: signature, message: message))
    }

    @Test func PublicKeyVerifyInvalidSignature() throws {
        let bls = try BLS.SecretKey(from: Data32.random())
        let publicKey = bls.publicKey
        let message = Data("testMessage".utf8)
        let signature = try bls.sign(message: message)

        // Corrupt the signature
        var invalidSignature = signature
        invalidSignature[0] ^= 0xFF // Flip a bit in the first byte

        // Test invalid signature verification
        #expect(try !publicKey.verify(signature: invalidSignature, message: message))
    }

    @Test func PublicKeyVerifyInvalidMessage() throws {
        let bls = try BLS.SecretKey(from: Data32.random())
        let publicKey = bls.publicKey
        let message = Data("testMessage".utf8)
        let invalidMessage = Data("invalidMessage".utf8)
        let signature = try bls.sign(message: message)

        // Test verification with an invalid message
        #expect(try !publicKey.verify(signature: signature, message: invalidMessage))
    }
}
