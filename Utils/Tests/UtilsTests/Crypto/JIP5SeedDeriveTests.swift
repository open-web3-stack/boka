import Foundation
import Testing
@testable import Utils

struct Vector {
    let index: UInt32
    let seedHex: String
    let ed25519SeedHex: String
    let ed25519PubHex: String
    let bandersnatchSeedHex: String
    let bandersnatchPubHex: String
}

// test vectors from JIP-5 spec
let vectors: [Vector] = [
    Vector(
        index: 0,
        seedHex: "0000000000000000000000000000000000000000000000000000000000000000",
        ed25519SeedHex: "996542becdf1e78278dc795679c825faca2e9ed2bf101bf3c4a236d3ed79cf59",
        ed25519PubHex: "4418fb8c85bb3985394a8c2756d3643457ce614546202a2f50b093d762499ace",
        bandersnatchSeedHex: "007596986419e027e65499cc87027a236bf4a78b5e8bd7f675759d73e7a9c799",
        bandersnatchPubHex: "ff71c6c03ff88adb5ed52c9681de1629a54e702fc14729f6b50d2f0a76f185b3"
    ),
    Vector(
        index: 1,
        seedHex: "0100000001000000010000000100000001000000010000000100000001000000",
        ed25519SeedHex: "b81e308145d97464d2bc92d35d227a9e62241a16451af6da5053e309be4f91d7",
        ed25519PubHex: "ad93247bd01307550ec7acd757ce6fb805fcf73db364063265b30a949e90d933",
        bandersnatchSeedHex: "12ca375c9242101c99ad5fafe8997411f112ae10e0e5b7c4589e107c433700ac",
        bandersnatchPubHex: "dee6d555b82024f1ccf8a1e37e60fa60fd40b1958c4bb3006af78647950e1b91"
    ),
    Vector(
        index: 2,
        seedHex: "0200000002000000020000000200000002000000020000000200000002000000",
        ed25519SeedHex: "0093c8c10a88ebbc99b35b72897a26d259313ee9bad97436a437d2e43aaafa0f",
        ed25519PubHex: "cab2b9ff25c2410fbe9b8a717abb298c716a03983c98ceb4def2087500b8e341",
        bandersnatchSeedHex: "3d71dc0ffd02d90524fda3e4a220e7ec514a258c59457d3077ce4d4f003fd98a",
        bandersnatchPubHex: "9326edb21e5541717fde24ec085000b28709847b8aab1ac51f84e94b37ca1b66"
    ),
    Vector(
        index: 3,
        seedHex: "0300000003000000030000000300000003000000030000000300000003000000",
        ed25519SeedHex: "69b3a7031787e12bfbdcac1b7a737b3e5a9f9450c37e215f6d3b57730e21001a",
        ed25519PubHex: "f30aa5444688b3cab47697b37d5cac5707bb3289e986b19b17db437206931a8d",
        bandersnatchSeedHex: "107a9148b39a1099eeaee13ac0e3c6b9c256258b51c967747af0f8749398a276",
        bandersnatchPubHex: "0746846d17469fb2f95ef365efcab9f4e22fa1feb53111c995376be8019981cc"
    ),
    Vector(
        index: 4,
        seedHex: "0400000004000000040000000400000004000000040000000400000004000000",
        ed25519SeedHex: "b4de9ebf8db5428930baa5a98d26679ab2a03eae7c791d582e6b75b7f018d0d4",
        ed25519PubHex: "8b8c5d436f92ecf605421e873a99ec528761eb52a88a2f9a057b3b3003e6f32a",
        bandersnatchSeedHex: "0bb36f5ba8e3ba602781bb714e67182410440ce18aa800c4cb4dd22525b70409",
        bandersnatchPubHex: "151e5c8fe2b9d8a606966a79edd2f9e5db47e83947ce368ccba53bf6ba20a40b"
    ),
    Vector(
        index: 5,
        seedHex: "0500000005000000050000000500000005000000050000000500000005000000",
        ed25519SeedHex: "4a6482f8f479e3ba2b845f8cef284f4b3208ba3241ed82caa1b5ce9fc6281730",
        ed25519PubHex: "ab0084d01534b31c1dd87c81645fd762482a90027754041ca1b56133d0466c06",
        bandersnatchSeedHex: "75e73b8364bf4753c5802021c6aa6548cddb63fe668e3cacf7b48cdb6824bb09",
        bandersnatchPubHex: "2105650944fcd101621fd5bb3124c9fd191d114b7ad936c1d79d734f9f21392e"
    ),
]

struct JIP5SeedDeriveTests {
    @Test(arguments: vectors)
    func testJIP5SeedDerivationAndPublicKeys(vector: Vector) throws {
        let seed = JIP5SeedDerive.trivialSeed(vector.index)
        #expect(seed.toHexString() == vector.seedHex)

        let derived = JIP5SeedDerive.deriveKeySeeds(from: seed)
        #expect(derived.ed25519.toHexString() == vector.ed25519SeedHex)
        #expect(derived.bandersnatch.toHexString() == vector.bandersnatchSeedHex)

        let ed25519Pub = try Ed25519.SecretKey(from: derived.ed25519).publicKey
        let bandersnatchPub = try Bandersnatch.SecretKey(from: derived.bandersnatch).publicKey
        #expect(ed25519Pub.data.toHexString() == vector.ed25519PubHex)
        #expect(bandersnatchPub.data.toHexString() == vector.bandersnatchPubHex)
    }
}
