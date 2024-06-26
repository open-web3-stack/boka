import XCTest

@testable import Utils

final class Ed25519Tests: XCTestCase {
    func testEd25519Signature() throws {
        let ed25519 = Ed25519()
        let publicKey = ed25519.publicKey

        let message = Data("test".utf8)
        let signature = try ed25519.sign(message: message)
        XCTAssertTrue(ed25519.verify(signature: signature, message: message, publicKey: publicKey))

        let invalidMessage = Data("tests".utf8)
        XCTAssertFalse(ed25519.verify(signature: signature, message: invalidMessage, publicKey: publicKey))

        var invalidSignature = signature.data
        invalidSignature.replaceSubrange(0 ... 1, with: [10, 12])
        XCTAssertFalse(ed25519.verify(signature: Data64(invalidSignature)!, message: message, publicKey: publicKey))
    }
}
