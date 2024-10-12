import Foundation
import Testing

@testable import Utils

@Suite struct BandersnatchTests {
    @Test func ringSignAndVerify() throws {
        var seed = Data(repeating: 0x12, count: 32)
        var keys = [Bandersnatch.SecretKey]()

        for i in 0 ..< 10 {
            seed[0] = UInt8(i)
            let secret = try Bandersnatch.SecretKey(from: Data32(seed)!)
            keys.append(secret)
        }

        let ctx = try Bandersnatch.RingContext(size: UInt(keys.count))
        let commitment = try Bandersnatch.RingCommitment(ring: keys.map(\.publicKey), ctx: ctx)

        let verifier = Bandersnatch.Verifier(ctx: ctx, commitment: commitment)

        for (i, key) in keys.enumerated() {
            let prover = Bandersnatch.Prover(sercret: key, ring: keys.map(\.publicKey), proverIdx: UInt(i), ctx: ctx)
            let vrfInputData = Data(repeating: UInt8(i), count: 32)
            let sig = try prover.ringVRFSign(vrfInputData: vrfInputData)
            let output = try verifier.ringVRFVerify(vrfInputData: vrfInputData, signature: sig)
            let vrfOutput = try keys[i].getOutput(vrfInputData: vrfInputData)
            #expect(output == vrfOutput)
        }
    }
}
