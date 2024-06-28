import blst
import XCTest

@testable import Utils

final class BlsTests: XCTestCase {
    func testBlsSignature() throws {
        // let ed25519 = Ed25519()
        // let publicKey = ed25519.publicKey
        var secretKey = blst_scalar()
        var ikm = byte(8)
        var info = byte(4)
        // let len = 8
        blst_keygen(&secretKey, &ikm, 8, &info, 4)
        print(secretKey.b)
    }
}
