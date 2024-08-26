import Foundation
import Testing

@testable import Utils

@Suite struct BLSTests {
    @Test func BLSSignatureWorks() throws {
        let bls = try BLS(ikm: Data("this is random high entropy ikm for key1".utf8))
        let publicKey1 = bls.publicKey
        let message1 = Data("test1".utf8)
        let signature1 = bls.sign(message: message1)

        #expect(
            BLS.verify(signature: signature1, message: message1, publicKey: publicKey1)
        )

        let invalidMessage = Data("testUnknown".utf8)
        #expect(
            !BLS.verify(signature: signature1, message: invalidMessage, publicKey: publicKey1)
        )

        var invalidSignature = signature1.data
        invalidSignature.replaceSubrange(0 ... 1, with: [2, 3])
        #expect(
            !BLS.verify(
                signature: Data96(invalidSignature)!, message: message1, publicKey: publicKey1
            )
        )

        let bls2 = try BLS(ikm: Data("this is random high entropy ikm for key2".utf8))
        let publicKey2 = bls2.publicKey
        let message2 = Data("test2".utf8)
        let signature2 = bls2.sign(message: message2)

        #expect(
            BLS.verify(signature: signature2, message: message2, publicKey: publicKey2)
        )

        let aggSig = try BLS.aggregateSignatures(signatures: [signature1, signature2])

        #expect(
            BLS.aggregateVerify(
                signature: aggSig, messages: [message1, message2],
                publicKeys: [publicKey1, publicKey2]
            )
        )

        #expect(
            !BLS.aggregateVerify(
                signature: aggSig, messages: [message1, message2],
                publicKeys: [publicKey2, publicKey1]
            )
        )
    }
}