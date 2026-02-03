import Foundation
@testable import JAMTests
import Testing
import Utils

struct Ed25519TestVector: Codable, CustomStringConvertible {
    let number: Int
    let desc: String
    let pk: String
    let r: String
    let s: String
    let msg: String
    let pk_canonical: Bool
    let r_canonical: Bool

    var description: String {
        "Vector #\(number): \(desc)"
    }
}

struct ED25519Tests {
    static func loadTestVectors() throws -> [Ed25519TestVector] {
        let data = try TestLoader.getFile(path: "crypto/ed25519/vectors", extension: "json", src: .fuzz)
        let decoder = JSONDecoder()
        return try decoder.decode([Ed25519TestVector].self, from: data)
    }

    @Test(arguments: try loadTestVectors())
    func ed25519Signature(vector: Ed25519TestVector) throws {
        let rBytes = try #require(Data(fromHexString: vector.r))
        let sBytes = try #require(Data(fromHexString: vector.s))
        let signature = Data64(rBytes + sBytes)!

        let pkBytes = try #require(Data(fromHexString: vector.pk))
        let publicKey = try Ed25519.PublicKey(from: #require(Data32(pkBytes)))

        let message = try #require(Data(fromHexString: vector.msg))
        let isValid = publicKey.verify(signature: signature, message: message)

        #expect(isValid, "\(vector.description) should verify correctly")
    }
}
