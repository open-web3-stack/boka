import Foundation
import MsQuicSwift
import Testing
import Utils

@testable import Networking

struct CertificateTests {
    @Test func certCheck() async throws {
        let certificate = try parseCertificate(data: certData)
        print("ParsedCertificate \(certificate.alternativeName)")
    }
}
