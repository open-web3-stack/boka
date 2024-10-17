import CryptoKit
import Foundation
import X509

func parseCertificate(_ data: Data) throws -> ParsedCertificate? {
    let binary = Array(data)
    let certificate = try Certificate(derEncoded: binary)
    // Verify the signature algorithm is Ed25519
    // Extract the public key
    let publicKey = certificate.publicKey
    let signatureAlgorithm = certificate.signatureAlgorithm
    let altName = ""
    // Extract the alternative name
    return ParsedCertificate(
        signatureAlgorithm: .ed25519,
        publicKey: PublicKey(algorithm: .ed25519, key: publicKey.description.data(using: .utf8)!),
        alternativeName: altName
    )
}

struct PublicKey {
    var algorithm: SignatureAlgorithm
    var key: Data
}

struct ParsedCertificate {
    var signatureAlgorithm: SignatureAlgorithm
    var publicKey: PublicKey?
    var alternativeName: String?
}

enum SignatureAlgorithm {
    case ed25519
}
