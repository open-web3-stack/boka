import bandersnatch_vrfs
import Foundation

enum BandersnatchError: Error {
    case createSecretFailed
    case deserializePubKeyFailed
    case generatePubKeyFailed
    case createProverFailed
    case createVerifierFailed
    case ringVRFSignFailed
    case ietfVRFSignFailed
    case verifyRingVrfFailed
    case verifyIetfVrfFailed
}

extension Data {
    init(cSecret: CSecret) {
        let tuple = cSecret._0
        // a short way to convert (UInt8, UInt8, ...) to [UInt8, UInt8, ...]
        let array: [UInt8] = Swift.withUnsafeBytes(of: tuple) {
            Array($0.bindMemory(to: UInt8.self))
        }
        self.init(array)
    }

    init(cPublic: CPublic) {
        let tuple = cPublic._0
        let array: [UInt8] = Swift.withUnsafeBytes(of: tuple) {
            Array($0.bindMemory(to: UInt8.self))
        }
        self.init(array)
    }
}

extension CPublic {
    private static func deserialize(data: Data) throws -> CPublic {
        let cPublicPtr = public_deserialize_compressed([UInt8](data), UInt(data.count))
        guard let cPublicPtr else {
            throw BandersnatchError.deserializePubKeyFailed
        }
        return CPublic(_0: cPublicPtr.pointee._0)
    }

    init(data: Data) throws {
        self = try CPublic.deserialize(data: data)
    }

    init(data32: Data32) throws {
        self = try CPublic.deserialize(data: data32.data)
    }
}

struct Bandersnatch {
    public let secret: Data96
    public let publicKey: Data32

    init(seed: Data) throws {
        let seedBytes = [UInt8](seed)
        let secretPtr = secret_new_from_seed(seedBytes, UInt(seed.count))
        guard let secretPtr else {
            throw BandersnatchError.createSecretFailed
        }

        secret = Data96(Data(cSecret: secretPtr.pointee))!

        let publicPtr = secret_get_public(secretPtr)
        guard let publicPtr else {
            throw BandersnatchError.generatePubKeyFailed
        }

        publicKey = Data32(Data(cPublic: publicPtr.pointee))!
    }
}

class Prover {
    private var prover: OpaquePointer

    /// init with a set of bandersnatch public keys and provider index
    init(ring: [Data32], proverIdx: UInt) throws {
        var success = false
        let cPublicArr = try ring.map { try CPublic(data32: $0) }
        prover = prover_new(cPublicArr, UInt(ring.count), proverIdx, &success)
        if !success {
            throw BandersnatchError.createProverFailed
        }
    }

    deinit {
        prover_free(prover)
    }

    /// Anonymous VRF signature.
    ///
    /// Used for tickets submission.
    func ringVRFSign(vrfInputData: Data, auxData: Data) throws -> Data784 {
        var output = [UInt8](repeating: 0, count: 784)
        let success = prover_ring_vrf_sign(
            &output, prover, [UInt8](vrfInputData), UInt(vrfInputData.count), [UInt8](auxData),
            UInt(auxData.count)
        )
        if !success {
            throw BandersnatchError.ringVRFSignFailed
        }
        return Data784(Data(output))!
    }

    /// Non-Anonymous VRF signature.
    ///
    /// Used for ticket claiming during block production.
    /// Not used with Safrole test vectors.
    func ietfVRFSign(vrfInputData: Data, auxData: Data) throws -> Data96 {
        var output = [UInt8](repeating: 0, count: 96)
        let success = prover_ietf_vrf_sign(
            &output, prover, [UInt8](vrfInputData), UInt(vrfInputData.count), [UInt8](auxData),
            UInt(auxData.count)
        )
        if !success {
            throw BandersnatchError.ietfVRFSignFailed
        }
        return Data96(Data(output))!
    }
}

class Verifier {
    private var verifier: OpaquePointer

    init(ring: [Data32]) throws {
        var success = false
        let cPublicArr = try ring.map { try CPublic(data32: $0) }
        verifier = verifier_new(cPublicArr, UInt(ring.count), &success)
        if !success {
            throw BandersnatchError.createVerifierFailed
        }
    }

    deinit {
        verifier_free(verifier)
    }

    /// Anonymous VRF signature verification.
    ///
    /// Used for tickets verification.
    ///
    /// On success returns the VRF output hash.
    func ringVRFVerify(vrfInputData: Data, auxData: Data, signature: Data) -> Result<
        Data32, BandersnatchError
    > {
        var output = [UInt8](repeating: 0, count: 32)
        let success = verifier_ring_vrf_verify(
            &output, verifier, [UInt8](vrfInputData), UInt(vrfInputData.count), [UInt8](auxData),
            UInt(auxData.count), [UInt8](signature), UInt(signature.count)
        )
        if !success {
            return .failure(.verifyRingVrfFailed)
        }
        return .success(Data32(Data(output))!)
    }

    /// Non-Anonymous VRF signature verification.
    ///
    /// Used for ticket claim verification during block import.
    /// Not used with Safrole test vectors.
    ///
    /// On success returns the VRF output hash.
    func ietfVRFVerify(vrfInputData: Data, auxData: Data, signature: Data, signerKeyIndex: UInt)
        -> Result<Data32, BandersnatchError>
    {
        var output = [UInt8](repeating: 0, count: 32)
        let success = verifier_ietf_vrf_verify(
            &output, verifier, [UInt8](vrfInputData), UInt(vrfInputData.count), [UInt8](auxData),
            UInt(auxData.count), [UInt8](signature), UInt(signature.count), signerKeyIndex
        )
        if !success {
            return .failure(.verifyIetfVrfFailed)
        }
        return .success(Data32(Data(output))!)
    }
}
