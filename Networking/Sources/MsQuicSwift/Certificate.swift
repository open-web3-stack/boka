import CHelpers
import Foundation

public struct ParsedCertificate {
    public let publicKey: Data
    public let alternativeName: String
}

enum CertificateError: Error {
    case parseFailed
}

public func parseCertificate(data: Data) throws -> ParsedCertificate {
    var publicKeyPointer: UnsafeMutablePointer<UInt8>?
    let publicKeyLen = 32
    var altNamePointer: UnsafeMutablePointer<Int8>?

    let result = data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
        parse_pkcs12_certificate(
            bytes.baseAddress!.assumingMemoryBound(to: UInt8.self),
            data.count,
            &publicKeyPointer,
            publicKeyLen,
            &altNamePointer
        )
    }
    print("result: \(result)")

    guard result == 0 else {
        throw CertificateError.parseFailed
    }

    let publicKeyData = Data(bytes: publicKeyPointer!, count: publicKeyLen)
    let alternativeName = String(cString: altNamePointer!)

    return ParsedCertificate(
        publicKey: publicKeyData,
        alternativeName: alternativeName
    )
}
