import Foundation
import Testing

@testable import Utils

@Suite struct Ed25519Tests {
    @Test func testEd25519Signature() throws {
        let ed25519 = try Ed25519.SecretKey(from: Data32.random())
        let publicKey = ed25519.publicKey

        let message = Data("test".utf8)
        let signature = try ed25519.sign(message: message)
        #expect(publicKey.verify(signature: signature, message: message))

        let invalidMessage = Data("tests".utf8)
        #expect(
            !publicKey.verify(signature: signature, message: invalidMessage)
        )

        var invalidSignature = signature.data
        invalidSignature.replaceSubrange(0 ... 1, with: [10, 12])
        #expect(
            !publicKey.verify(signature: Data64(invalidSignature)!, message: message)
        )
    }
}
