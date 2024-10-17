import Foundation
import MsQuicSwift
import Testing
import Utils

@testable import Networking

struct CertificateTests {
    @Test func certCheck() async throws {
        let privateKey = try Ed25519.SecretKey(from: Data32())
        let cert = try generateSelfSignedCertificate(privateKey: privateKey)
        let certificate = try parseCertificate(data: cert)
        print("ParsedCertificate \(certificate.alternativeName)")
    }
}
