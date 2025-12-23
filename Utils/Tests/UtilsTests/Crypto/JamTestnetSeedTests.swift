import Foundation
import Testing

@testable import Utils

struct JamTestnetSeedTests {
    @Test func alice() throws {
        let seed = Data32(fromHexString: "0000000000000000000000000000000000000000000000000000000000000000")!
        let bandersnatch = try Bandersnatch.SecretKey(from: seed)
        let ed25519 = try Ed25519.SecretKey(from: seed)
        let bls = try BLS.SecretKey(from: seed)
        #expect(bandersnatch.publicKey.data.toHexString() == "5e465beb01dbafe160ce8216047f2155dd0569f058afd52dcea601025a8d161d")
        #expect(ed25519.publicKey.data.toHexString() == "3b6a27bcceb6a42d62a3a8d02a6f0d73653215771de243a63ac048a18b59da29")
        #expect(bls.publicKey.data.toHexString() ==
            // swiftlint:disable:next line_length
            "b27150a1f1cd24bccc792ba7ba4220a1e8c36636e35a969d1d14b4c89bce7d1d463474fb186114a89dd70e88506fefc9830756c27a7845bec1cb6ee31e07211afd0dde34f0dc5d89231993cd323973faa23d84d521fd574e840b8617c75d1a1d0102aa3c71999137001a77464ced6bb2885c460be760c709009e26395716a52c8c52e6e23906a455b4264e7d0c75466e")
    }

    @Test func bob() throws {
        let seed = Data32(fromHexString: "0000000000000000000000000000000000000000000000000000000000000001")!
        let bandersnatch = try Bandersnatch.SecretKey(from: seed)
        let ed25519 = try Ed25519.SecretKey(from: seed)
        let bls = try BLS.SecretKey(from: seed)
        #expect(bandersnatch.publicKey.data.toHexString() == "1565283e47871f63e863b3c78dc82c9a62ad3040027a7996c827e2461cbf1571")
        #expect(ed25519.publicKey.data.toHexString() == "4cb5abf6ad79fbf5abbccafcc269d85cd2651ed4b885b5869f241aedf0a5ba29")
        #expect(bls.publicKey.data.toHexString() ==
            // swiftlint:disable:next line_length
            "8b8a096ada14a51df7e2067007bf6c24d7568d88bf89816c1287ba2784b4188c3536d70b1a1cbc8ab438056e457e2aa0ab48d30d6279373652d19269f7260624d0965c3dc00ed944d1b6ff6db06bb73dc1314164e9fed6020108487897ac3a9814eca841aedc47f504a848513166ffe39f89c9f3e7c6729dc99207f863a10bda142d5a24ba42b90d99d6d6df3fa6d780")
    }

    @Test func charlie() throws {
        let seed = Data32(fromHexString: "0000000000000000000000000000000000000000000000000000000000000002")!
        let bandersnatch = try Bandersnatch.SecretKey(from: seed)
        let ed25519 = try Ed25519.SecretKey(from: seed)
        let bls = try BLS.SecretKey(from: seed)
        #expect(bandersnatch.publicKey.data.toHexString() == "699a8fcb24649d8f159a5bd11916cb9541dc5360690c06935ecdf3b6d06cce01")
        #expect(ed25519.publicKey.data.toHexString() == "7422b9887598068e32c4448a949adb290d0f4e35b9e01b0ee5f1a1e600fe2674")
        #expect(bls.publicKey.data.toHexString() ==
            // swiftlint:disable:next line_length
            "93377fa4dddd7cf95dddef8edfe9ff310ba4d8dffa57e34f2774ad2a6adb16e8ebca12e037dcaf5d762d8eaa9b9cb40498b771e65d8364b1af4cbf51b41525df62b78d8507218c14d9af1eeb96bec770646b9f2b887518b3248f8d8d526874231255aa247b7e252c0802be0a91cc659a0f4b679487345ab8a5f5d67b53319d6ad7d946b9976be4deab9e9a7f2486ecb1")
    }
}
