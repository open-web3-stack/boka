import Foundation
import Testing
import Utils

@testable import Networking

struct PKCS12Tests {
    @Test func generate() async throws {
        let privateKey = try Ed25519.SecretKey(from: Data32())
        let cert = try generateSelfSignedCertificate(privateKey: privateKey)
        print("len: \(cert.count)")
        print(cert.toHexString())
        #expect(cert.count > 0)
    }
}
