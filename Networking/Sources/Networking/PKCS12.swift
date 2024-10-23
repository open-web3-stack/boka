import CHelpers
import Foundation
import Utils

enum CryptoError: Error {
    case generateFailed(String)
    case parseFailed(String)
}

public enum CertificateType {
    case x509
    case p12
}

public func parseCertificate(data: Data, type: CertificateType) throws -> (
    publicKey: Data, alternativeName: String
) {
    var publicKeyPointer: UnsafeMutablePointer<UInt8>!
    var publicKeyLen = 0
    var altNamePointer: UnsafeMutablePointer<Int8>!
    var errorMessage: UnsafeMutablePointer<Int8>?
    defer { free(altNamePointer) }

    let result: Int32 =
        switch type {
        case .x509:
            data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                parse_certificate(
                    bytes.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    data.count,
                    &publicKeyPointer,
                    &publicKeyLen,
                    &altNamePointer,
                    &errorMessage
                )
            }
        case .p12:
            data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                parse_pkcs12_certificate(
                    bytes.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    data.count,
                    &publicKeyPointer,
                    &publicKeyLen,
                    &altNamePointer,
                    &errorMessage
                )
            }
        }

    guard result == 0 else {
        throw CryptoError.parseFailed(String(cString: errorMessage!))
    }

    let publicKeyData = Data(
        bytesNoCopy: publicKeyPointer, count: Int(publicKeyLen), deallocator: .free
    )
    let alternativeName = String(cString: altNamePointer)
    return (publicKey: publicKeyData, alternativeName: alternativeName)
}

public func generateSelfSignedCertificate(privateKey: Ed25519.SecretKey) throws -> Data {
    let publicKey = privateKey.publicKey

    let secretKeyData = privateKey.rawRepresentation

    let altName = generateSubjectAlternativeName(publicKey: publicKey)

    var pkcs12Data: UnsafeMutablePointer<UInt8>!
    var pkcs12Length: Int32 = 0

    let ret = altName.withCString { altNamePtr in
        secretKeyData.withUnsafeBytes { secretKeyDataPtr in
            generate_self_signed_cert_and_pkcs12(
                secretKeyDataPtr.baseAddress,
                secretKeyDataPtr.count,
                altNamePtr,
                &pkcs12Data,
                &pkcs12Length
            )
        }
    }
    if ret != 0 {
        let errorCStr = get_error_string(ret)!
        let errorStr = String(cString: errorCStr)
        throw CryptoError.generateFailed(errorStr)
    }

    return Data(bytesNoCopy: pkcs12Data, count: Int(pkcs12Length), deallocator: .free)
}

func generateSubjectAlternativeName(publicKey: Ed25519.PublicKey) -> String {
    let base32Encoded = base32Encode(publicKey.data.data)
    return "DNS:e\(base32Encoded)"
}

func generateSubjectAlternativeName(pubkey: Data) -> String {
    let base32Encoded = base32Encode(pubkey)
    return "DNS:e\(base32Encoded)"
}

func base32Encode(_ data: Data) -> String {
    let alphabet = "abcdefghijklmnopqrstuvwxyz234567"
    // Implement base32 encoding using the specified alphabet
    // This is a simplified version and may need adjustment
    var result = ""
    var bits = 0
    var value = 0
    for byte in data {
        value = (value << 8) | Int(byte)
        bits += 8
        while bits >= 5 {
            bits -= 5
            let index = (value >> bits) & 31
            result.append(alphabet[alphabet.index(alphabet.startIndex, offsetBy: index)])
        }
    }
    if bits > 0 {
        let index = (value << (5 - bits)) & 31
        result.append(alphabet[alphabet.index(alphabet.startIndex, offsetBy: index)])
    }
    return result
}
