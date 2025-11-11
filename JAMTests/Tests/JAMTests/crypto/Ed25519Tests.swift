import Foundation
import Testing
import Utils

@testable import JAMTests

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
    func testEd25519Signature(vector: Ed25519TestVector) throws {
        let rBytes = Data(fromHexString: vector.r)!
        let sBytes = Data(fromHexString: vector.s)!
        let signature = Data64(rBytes + sBytes)!

        let pkBytes = Data(fromHexString: vector.pk)!
        let publicKey = try Ed25519.PublicKey(from: Data32(pkBytes)!)

        let message = Data(fromHexString: vector.msg)!
        let isValid = publicKey.verify(signature: signature, message: message)

        #expect(isValid, "\(vector.description) should verify correctly")
    }
}
