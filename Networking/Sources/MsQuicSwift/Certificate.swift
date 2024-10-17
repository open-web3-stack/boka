import CHelpers
import Foundation

public struct ParsedCertificate {
    public let publicKey: Data
    public let alternativeName: String
}

public func parseCertificate(data: Data) throws -> ParsedCertificate {
    var publicKeyPointer: UnsafeMutablePointer<UInt8>?
    var publicKeyLen = 0
    var altNamePointer: UnsafeMutablePointer<Int8>?

    let result = data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
        parse_certificate(
            bytes.baseAddress!.assumingMemoryBound(to: UInt8.self),
            data.count,
            &publicKeyPointer,
            &publicKeyLen,
            &altNamePointer
        )
    }

    guard result == 0 else {
        throw NSError(domain: "CertificateParsingError", code: 1, userInfo: nil)
    }

    let publicKeyData = Data(bytes: publicKeyPointer!, count: publicKeyLen)
    let alternativeName = String(cString: altNamePointer!)

    return ParsedCertificate(
        publicKey: publicKeyData,
        alternativeName: alternativeName
    )
}
