import bandersnatch_vrfs
import Foundation

private func _call<E: Error>(
    data: [Data],
    out: inout Data?,
    fn: ([(ptr: UnsafeRawPointer, count: UInt)], (ptr: UnsafeMutableRawPointer, count: UInt)?) -> Int,
    onErr: (Int) throws(E) -> Void
) throws(E) {
    func helper(data: ArraySlice<Data>, ptr: [(ptr: UnsafeRawPointer, count: UInt)]) -> Int {
        if data.isEmpty {
            if var outData = out {
                let res = outData.withUnsafeMutableBytes { (bufferPtr: UnsafeMutableRawBufferPointer) -> Int in
                    guard let bufferAddress = bufferPtr.baseAddress else {
                        fatalError("unreachable: bufferPtr.baseAddress is nil")
                    }
                    return fn(ptr, (ptr: bufferAddress, count: UInt(bufferPtr.count)))
                }
                out = outData
                return res
            }
            return fn(ptr, nil)
        }
        let rest = data.dropFirst()
        let first = data.first!
        return first.withUnsafeBytes { (bufferPtr: UnsafeRawBufferPointer) -> Int in
            guard let bufferAddress = bufferPtr.baseAddress else {
                fatalError("unreachable: bufferPtr.baseAddress is nil")
            }
            return helper(data: rest, ptr: ptr + [(bufferAddress, UInt(bufferPtr.count))])
        }
    }

    let ret = helper(data: data[...], ptr: [])

    if ret != 0 {
        try onErr(ret)
    }
}

private func call<E: Error>(
    _ data: Data...,
    fn: ([(ptr: UnsafeRawPointer, count: UInt)]) -> Int,
    onErr: (Int) throws(E) -> Void
) throws(E) {
    var out: Data?
    try _call(data: data, out: &out, fn: { ptrs, _ in fn(ptrs) }, onErr: onErr)
}

private func call(
    _ data: Data...,
    fn: ([(ptr: UnsafeRawPointer, count: UInt)]) -> Int
) {
    var out: Data?
    _call(data: data, out: &out, fn: { ptrs, _ in fn(ptrs) }, onErr: { err in fatalError("unreachable: \(err)") })
}

private func call<E: Error>(
    _ data: Data...,
    out: inout Data,
    fn: ([(ptr: UnsafeRawPointer, count: UInt)], (ptr: UnsafeMutableRawPointer, count: UInt)) -> Int,
    onErr: (Int) throws(E) -> Void
) throws(E) {
    var out2: Data? = out
    try _call(data: data, out: &out2, fn: { ptrs, out_buf in fn(ptrs, out_buf!) }, onErr: onErr)
    out = out2!
}

private func call(
    _ data: Data...,
    out: inout Data,
    fn: ([(ptr: UnsafeRawPointer, count: UInt)], (ptr: UnsafeMutableRawPointer, count: UInt)) -> Int
) {
    var out2: Data? = out
    _call(data: data, out: &out2, fn: { ptrs, out_buf in fn(ptrs, out_buf!) }, onErr: { err in fatalError("unreachable: \(err)") })
    out = out2!
}

public enum Bandersnatch: KeyType {
    public enum Error: Swift.Error {
        case createSecretFailed(Int)
        case createPublicKeyFailed(Int)
        case createRingContextFailed(Int)
        case ringVRFSignFailed(Int)
        case ietfVRFSignFailed(Int)
        case createRingCommitmentFailed(Int)
        case serializeRingCommitmentFailed(Int)
        case ringVRFVerifyFailed(Int)
        case ietfVRFVerifyFailed(Int)
    }

    public final class SecretKey: SecretKeyProtocol, @unchecked Sendable {
        fileprivate let ptr: OpaquePointer
        public let publicKey: PublicKey

        public init(from seed: Data32) throws(Error) {
            var ptr: OpaquePointer!

            try call(seed.data) { ptrs in
                secret_new(ptrs[0].ptr, ptrs[0].count, &ptr)
            } onErr: { err throws(Error) in
                throw .createSecretFailed(err)
            }

            self.ptr = ptr
            publicKey = try PublicKey(secretKey: ptr)
        }

        deinit {
            secret_free(ptr)
        }

        /// Non-Anonymous VRF signature.
        ///
        /// Used for ticket claiming during block production.
        public func ietfVRFSign(vrfInputData: Data, auxData: Data) throws -> Data96 {
            var output = Data(repeating: 0, count: 96)

            try call(vrfInputData, auxData, out: &output) { ptrs, out_buf in
                prover_ietf_vrf_sign(
                    ptr,
                    ptrs[0].ptr,
                    ptrs[0].count,
                    ptrs[1].ptr,
                    ptrs[1].count,
                    out_buf.ptr,
                    out_buf.count
                )
            } onErr: { err throws(Error) in
                throw .ietfVRFSignFailed(err)
            }

            return Data96(Data(output))!
        }
    }

    public final class PublicKey: PublicKeyProtocol, Hashable, @unchecked Sendable, CustomStringConvertible {
        fileprivate let ptr: OpaquePointer
        public let data: Data32

        public init(data: Data32) throws(Error) {
            var ptr: OpaquePointer!
            try call(data.data) { ptrs in
                public_new_from_data(ptrs[0].ptr, ptrs[0].count, &ptr)
            } onErr: { err throws(Error) in
                throw .createPublicKeyFailed(err)
            }
            self.ptr = ptr
            self.data = data
        }

        fileprivate init(secretKey: OpaquePointer) throws(Error) {
            var ptr: OpaquePointer!
            try call { _ in
                public_new_from_secret(secretKey, &ptr)
            } onErr: { err throws(Error) in
                throw .createRingContextFailed(err)
            }

            var data = Data(repeating: 0, count: 32)
            call(out: &data) { _, out_buf in
                public_serialize_compressed(ptr, out_buf.ptr, out_buf.count)
            }

            self.ptr = ptr
            self.data = Data32(data)!
        }

        deinit {
            public_free(ptr)
        }

        public convenience init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let data = try container.decode(Data32.self)
            try self.init(data: data)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(data)
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(data)
        }

        public static func == (lhs: PublicKey, rhs: PublicKey) -> Bool {
            lhs.data == rhs.data
        }

        public var description: String {
            "0x\(data.toHexString())"
        }

        /// Non-Anonymous VRF signature verification.
        ///
        /// Used for ticket claim verification during block import.
        /// Not used with Safrole test vectors.
        ///
        /// On success returns the VRF output hash.
        public func ietfVRFVerify(
            vrfInputData: Data, auxData: Data = Data(), signature: Data
        ) throws(Error) -> Data32 {
            var output = Data(repeating: 0, count: 32)

            try call(vrfInputData, auxData, signature, out: &output) { ptrs, out_buf in
                verifier_ietf_vrf_verify(
                    ptr,
                    ptrs[0].ptr,
                    ptrs[0].count,
                    ptrs[1].ptr,
                    ptrs[1].count,
                    ptrs[2].ptr,
                    ptrs[2].count,
                    out_buf.ptr,
                    out_buf.count
                )
            } onErr: { err throws(Error) in
                throw .ietfVRFVerifyFailed(err)
            }

            return Data32(output)!
        }
    }

    public final class RingContext: @unchecked Sendable {
        fileprivate let ptr: OpaquePointer

        public init(size: UInt) throws(Error) {
            var ptr: OpaquePointer!
            try call { _ in
                ring_context_new(size, &ptr)
            } onErr: { err throws(Error) in
                throw .createRingContextFailed(err)
            }
            self.ptr = ptr
        }

        deinit {
            ring_context_free(ptr)
        }
    }

    public final class Prover {
        private let secret: SecretKey
        private let ring: [PublicKey]
        private let ringPtrs: [OpaquePointer?]
        private let proverIdx: UInt
        private let ctx: RingContext

        public init(sercret: SecretKey, ring: [PublicKey], proverIdx: UInt, ctx: RingContext) {
            secret = sercret
            self.ring = ring
            self.proverIdx = proverIdx
            self.ctx = ctx
            ringPtrs = ring.map(\.ptr)
        }

        /// Anonymous VRF signature.
        ///
        /// Used for tickets submission.
        public func ringVRFSign(vrfInputData: Data, auxData: Data = Data()) throws(Error) -> Data784 {
            var output = Data(repeating: 0, count: 784)

            try call(vrfInputData, auxData, out: &output) { ptrs, out_buf in
                ringPtrs.withUnsafeBufferPointer { ringPtrs in
                    prover_ring_vrf_sign(
                        secret.ptr,
                        ringPtrs.baseAddress,
                        UInt(ringPtrs.count),
                        proverIdx,
                        ctx.ptr,
                        ptrs[0].ptr,
                        ptrs[0].count,
                        ptrs[1].ptr,
                        ptrs[1].count,
                        out_buf.ptr,
                        out_buf.count
                    )
                }
            } onErr: { err throws(Error) in
                throw .ringVRFSignFailed(err)
            }

            return Data784(output)!
        }
    }

    public final class RingCommitment: @unchecked Sendable {
        fileprivate let ptr: OpaquePointer
        public let data: Data144

        public init(ring: [PublicKey], ctx: RingContext) throws(Error) {
            let ringPtrs = ring.map { $0.ptr as OpaquePointer? }

            var ptr: OpaquePointer!
            try call { _ in
                ringPtrs.withUnsafeBufferPointer { ringPtrs in
                    ring_commitment_new_from_ring(
                        ringPtrs.baseAddress,
                        UInt(ringPtrs.count),
                        ctx.ptr,
                        &ptr
                    )
                }

            } onErr: { err throws(Error) in
                throw .createRingCommitmentFailed(err)
            }

            var out = Data(repeating: 0, count: 144)
            try call(out: &out) { _, out_buf in
                ring_commitment_serialize(ptr, out_buf.ptr, out_buf.count)
            } onErr: { err throws(Error) in
                throw .serializeRingCommitmentFailed(err)
            }

            self.ptr = ptr
            data = Data144(out)!
        }

        public init(data: Data144) throws(Error) {
            var ptr: OpaquePointer!
            try call(data.data) { ptrs in
                ring_commitment_new_from_data(ptrs[0].ptr, ptrs[0].count, &ptr)
            } onErr: { err throws(Error) in
                throw .createRingCommitmentFailed(err)
            }
            self.ptr = ptr
            self.data = data
        }

        deinit {
            ring_commitment_free(ptr)
        }
    }

    public struct Verifier: Sendable {
        private let ctx: RingContext
        private let commitment: RingCommitment

        public init(ctx: RingContext, commitment: RingCommitment) {
            self.ctx = ctx
            self.commitment = commitment
        }

        /// Anonymous VRF signature verification.
        ///
        /// Used for tickets verification.
        ///
        /// On success returns the VRF output hash.
        public func ringVRFVerify(vrfInputData: Data, auxData: Data = Data(), signature: Data) throws(Error) -> Data32 {
            var output = Data(repeating: 0, count: 32)

            try call(vrfInputData, auxData, signature, out: &output) { ptrs, out_buf in
                verifier_ring_vrf_verify(
                    ctx.ptr,
                    commitment.ptr,
                    ptrs[0].ptr,
                    ptrs[0].count,
                    ptrs[1].ptr,
                    ptrs[1].count,
                    ptrs[2].ptr,
                    ptrs[2].count,
                    out_buf.ptr,
                    out_buf.count
                )
            } onErr: { err throws(Error) in
                throw .ringVRFVerifyFailed(err)
            }

            return Data32(output)!
        }
    }
}
