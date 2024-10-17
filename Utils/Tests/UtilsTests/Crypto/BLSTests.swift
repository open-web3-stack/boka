import Foundation
import Testing

@testable import Utils

@Suite struct BLSTests {
    @Test func BLSSignatureWorks() throws {
        let bls = try BLS.SecretKey(from: Data32())
        let publicKey1 = bls.publicKey
        #expect(publicKey1.data.data.count == 144)
        let message1 = Data("test1".utf8)
        let signature1 = try bls.sign(message: message1)
        #expect(signature1.count == 160)

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
}
