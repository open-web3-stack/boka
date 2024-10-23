import bandersnatch_vrfs
import Foundation
import TracingUtils

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
        case getOutputFailed(Int)
    }

    public final class SecretKey: SecretKeyProtocol, Sendable {
        fileprivate let ptr: SafePointer
        public let publicKey: PublicKey

        public init(from seed: Data32) throws(Error) {
            var ptr: OpaquePointer!

            try FFIUtils.call(seed.data) { ptrs in
                secret_new(ptrs[0].ptr, ptrs[0].count, &ptr)
            } onErr: { err throws(Error) in
                throw .createSecretFailed(err)
            }

            self.ptr = SafePointer(ptr: ptr.asSendable, free: secret_free)
            publicKey = try PublicKey(secretKey: self.ptr.ptr.value)
        }

        /// Non-Anonymous VRF signature.
        ///
        /// Used for ticket claiming during block production.
        public func ietfVRFSign(vrfInputData: Data, auxData: Data = Data()) throws -> Data96 {
            var output = Data(repeating: 0, count: 96)

            try FFIUtils.call(vrfInputData, auxData, out: &output) { ptrs, out_buf in
                prover_ietf_vrf_sign(
                    ptr.ptr.value,
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

        public func getOutput(vrfInputData: Data) throws -> Data32 {
            var output = Data(repeating: 0, count: 32)

            try FFIUtils.call(vrfInputData, out: &output) { ptrs, out_buf in
                secret_output(
                    ptr.ptr.value,
                    ptrs[0].ptr,
                    ptrs[0].count,
                    out_buf.ptr,
                    out_buf.count
                )
            } onErr: { err throws(Error) in
                throw .getOutputFailed(err)
            }

            return Data32(output)!
        }
    }

    public final class PublicKey: PublicKeyProtocol, Hashable, Sendable, CustomStringConvertible {
        fileprivate let ptr: SendableOpaquePointer
        public let data: Data32

        public init(data: Data32) throws(Error) {
            var ptr: OpaquePointer!
            try FFIUtils.call(data.data) { ptrs in
                public_new_from_data(ptrs[0].ptr, ptrs[0].count, &ptr)
            } onErr: { err throws(Error) in
                throw .createPublicKeyFailed(err)
            }
            self.ptr = ptr.asSendable
            self.data = data
        }

        fileprivate init(secretKey: OpaquePointer) throws(Error) {
            var ptr: OpaquePointer!
            try FFIUtils.call { _ in
                public_new_from_secret(secretKey, &ptr)
            } onErr: { err throws(Error) in
                throw .createRingContextFailed(err)
            }

            var data = Data(repeating: 0, count: 32)
            FFIUtils.call(out: &data) { _, out_buf in
                public_serialize_compressed(ptr, out_buf.ptr, out_buf.count)
            }

            self.ptr = ptr.asSendable
            self.data = Data32(data)!
        }

        deinit {
            public_free(ptr.value)
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
            data.description
        }

        /// Non-Anonymous VRF signature verification.
        ///
        /// Used for ticket claim verification during block import.
        /// Not used with Safrole test vectors.
        ///
        /// On success returns the VRF output hash.
        public func ietfVRFVerify(
            vrfInputData: Data, auxData: Data = Data(), signature: Data96
        ) throws(Error) -> Data32 {
            var output = Data(repeating: 0, count: 32)

            try FFIUtils.call(vrfInputData, auxData, signature.data, out: &output) { ptrs, out_buf in
                verifier_ietf_vrf_verify(
                    ptr.value,
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

    public final class RingContext: Sendable {
        fileprivate let ptr: SendableOpaquePointer

        public init(size: UInt) throws(Error) {
            var ptr: OpaquePointer!
            try FFIUtils.call { _ in
                ring_context_new(size, &ptr)
            } onErr: { err throws(Error) in
                throw .createRingContextFailed(err)
            }
            self.ptr = ptr.asSendable
        }

        deinit {
            ring_context_free(ptr.value)
        }
    }

    public final class Prover {
        private let secret: SecretKey
        private let ring: [PublicKey?]
        private let ringPtrs: [OpaquePointer?]
        private let proverIdx: UInt
        private let ctx: RingContext

        public init(sercret: SecretKey, ring: [PublicKey?], proverIdx: UInt, ctx: RingContext) {
            secret = sercret
            self.ring = ring
            self.proverIdx = proverIdx
            self.ctx = ctx
            ringPtrs = ring.map { $0?.ptr.value }
        }

        /// Anonymous VRF signature.
        ///
        /// Used for tickets submission.
        public func ringVRFSign(vrfInputData: Data, auxData: Data = Data()) throws(Error) -> Data784 {
            var output = Data(repeating: 0, count: 784)

            try FFIUtils.call(vrfInputData, auxData, out: &output) { ptrs, out_buf in
                ringPtrs.withUnsafeBufferPointer { ringPtrs in
                    prover_ring_vrf_sign(
                        secret.ptr.ptr.value,
                        ringPtrs.baseAddress,
                        UInt(ringPtrs.count),
                        proverIdx,
                        ctx.ptr.value,
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

    public final class RingCommitment: Sendable {
        fileprivate let ptr: SendableOpaquePointer
        public let data: Data144

        public init(ring: [PublicKey?], ctx: RingContext) throws(Error) {
            let ringPtrs = ring.map { $0?.ptr.value as OpaquePointer? }

            var ptr: OpaquePointer!
            try FFIUtils.call { _ in
                ringPtrs.withUnsafeBufferPointer { ringPtrs in
                    ring_commitment_new_from_ring(
                        ringPtrs.baseAddress,
                        UInt(ringPtrs.count),
                        ctx.ptr.value,
                        &ptr
                    )
                }

            } onErr: { err throws(Error) in
                throw .createRingCommitmentFailed(err)
            }

            var out = Data(repeating: 0, count: 144)
            try FFIUtils.call(out: &out) { _, out_buf in
                ring_commitment_serialize(ptr, out_buf.ptr, out_buf.count)
            } onErr: { err throws(Error) in
                throw .serializeRingCommitmentFailed(err)
            }

            self.ptr = ptr.asSendable
            data = Data144(out)!
        }

        public init(data: Data144) throws(Error) {
            var ptr: OpaquePointer!
            try FFIUtils.call(data.data) { ptrs in
                ring_commitment_new_from_data(ptrs[0].ptr, ptrs[0].count, &ptr)
            } onErr: { err throws(Error) in
                throw .createRingCommitmentFailed(err)
            }
            self.ptr = ptr.asSendable
            self.data = data
        }

        deinit {
            ring_commitment_free(ptr.value)
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
        public func ringVRFVerify(vrfInputData: Data, auxData: Data = Data(), signature: Data784) throws(Error) -> Data32 {
            var output = Data(repeating: 0, count: 32)

            try FFIUtils.call(vrfInputData, auxData, signature.data, out: &output) { ptrs, out_buf in
                verifier_ring_vrf_verify(
                    ctx.ptr.value,
                    commitment.ptr.value,
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
