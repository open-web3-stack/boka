import CHelpers
import Foundation
import Utils

enum CryptoError: Error {
    case generateFailed(String)
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
