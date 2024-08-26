import blst
import Foundation

enum BLSError: Error {
    case ikmTooShort
    case blstError(BLST_ERROR)
}

/// A wrapper to blst C library.
///
/// `blst_p1` for public keys, and `blst_p2` for signatures
public struct BLS {
    public let secretKey: Data32

    public let publicKey: Data48

    /// Initiate a BLS secret key with IKM.
    /// IKM MUST be infeasible to guess, e.g., generated by a trusted source of randomness.
    /// IKM MUST be at least 32 bytes long, but it MAY be longer.
    public init(ikm: Data) throws {
        guard ikm.count >= 32 else {
            throw BLSError.ikmTooShort
        }

        var sk = blst_scalar()
        let ikmBytes = [UInt8](ikm)
        let ikmLen = ikmBytes.count

        blst_keygen(&sk, ikmBytes, ikmLen, nil, 0)

        var out = [UInt8](repeating: 0, count: 32)
        blst_bendian_from_scalar(&out, &sk)

        secretKey = Data32(Data(out))!
        publicKey = BLS.getPublicKey(secretKey)
    }

    public init(privateKey: Data32) throws {
        var sk = blst_scalar()
        blst_scalar_from_bendian(&sk, [UInt8](privateKey.data))

        guard blst_sk_check(&sk) else {
            throw BLSError.blstError(BLST_BAD_SCALAR)
        }

        secretKey = privateKey
        publicKey = BLS.getPublicKey(secretKey)
    }

    private static func getPublicKey(_ secretKey: Data32) -> Data48 {
        var sk = blst_scalar()
        blst_scalar_from_bendian(&sk, [UInt8](secretKey.data))

        var pk = blst_p1()
        blst_sk_to_pk_in_g1(&pk, &sk)

        var pkBytes = [UInt8](repeating: 0, count: 48)
        blst_p1_compress(&pkBytes, &pk)

        return Data48(Data(pkBytes))!
    }

    public func sign(message: Data) -> Data96 {
        var sk = blst_scalar()
        blst_scalar_from_bendian(&sk, [UInt8](secretKey.data))

        var msgHash = blst_p2()
        blst_hash_to_g2(&msgHash, [UInt8](message), message.count, nil, 0, nil, 0)

        var sig = blst_p2()
        blst_sign_pk_in_g1(&sig, &msgHash, &sk)

        var sigBytes = [UInt8](repeating: 0, count: 96)
        blst_p2_compress(&sigBytes, &sig)

        return Data96(Data(sigBytes))!
    }

    public static func verify(signature: Data96, message: Data, publicKey: Data48) -> Bool {
        var pk = blst_p1_affine()
        var sig = blst_p2_affine()

        let pkResult = blst_p1_uncompress(&pk, [UInt8](publicKey.data))
        let sigResult = blst_p2_uncompress(&sig, [UInt8](signature.data))

        guard pkResult == BLST_SUCCESS, sigResult == BLST_SUCCESS else {
            return false
        }

        let verifyResult = blst_core_verify_pk_in_g1(
            &pk, &sig, true, [UInt8](message), message.count, nil, 0, nil, 0
        )

        return verifyResult == BLST_SUCCESS
    }

    public static func aggregateVerify(
        signature: Data96, messages: [Data], publicKeys: [Data48]
    )
        -> Bool
    {
        let size = blst_pairing_sizeof()
        let ctx = OpaquePointer(malloc(size))

        blst_pairing_init(ctx, true, nil, 0)

        var sig = blst_p2_affine()
        let sigResult = blst_p2_uncompress(&sig, [UInt8](signature.data))
        guard sigResult == BLST_SUCCESS else {
            return false
        }

        for i in 0 ..< publicKeys.count {
            var pk = blst_p1_affine()
            let pkResult = blst_p1_uncompress(&pk, [UInt8](publicKeys[i].data))
            guard pkResult == BLST_SUCCESS else {
                return false
            }

            let aggregateResult: BLST_ERROR =
                if i == 1 {
                    blst_pairing_aggregate_pk_in_g1(
                        ctx, &pk, &sig, [UInt8](messages[i]), messages[i].count, nil, 0
                    )
                } else {
                    blst_pairing_aggregate_pk_in_g1(
                        ctx, &pk, nil, [UInt8](messages[i]), messages[i].count, nil, 0
                    )
                }
            guard aggregateResult == BLST_SUCCESS else {
                return false
            }
        }

        blst_pairing_commit(ctx)
        let result = blst_pairing_finalverify(ctx, nil)

        free(UnsafeMutableRawPointer(ctx))

        return result
    }

    public static func aggregateSignatures(signatures: [Data96]) throws -> Data96 {
        var aggregate = blst_p2()

        for signature in signatures {
            var sig = blst_p2_affine()
            let sigResult = blst_p2_uncompress(&sig, [UInt8](signature.data))
            guard sigResult == BLST_SUCCESS else {
                throw BLSError.blstError(sigResult)
            }
            var aggCopy = aggregate
            blst_p2_add_or_double_affine(&aggregate, &aggCopy, &sig)
        }

        var sigCompressed = [UInt8](repeating: 0, count: 96)
        blst_p2_compress(&sigCompressed, &aggregate)

        return Data96(Data(sigCompressed))!
    }
}