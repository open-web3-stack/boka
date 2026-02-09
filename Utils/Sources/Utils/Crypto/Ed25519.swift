import ed25519_zebra_ffi
import Foundation

public enum Ed25519: KeyType {
    public enum Error: Swift.Error {
        case createSigningKeyFailed(Int)
        case createVerificationKeyFailed(Int)
        case signFailed(Int)
        case exportKeyFailed(Int)
    }

    public final class SecretKey: SecretKeyProtocol, @unchecked Sendable {
        fileprivate let ptr: SafePointer
        public let publicKey: PublicKey

        public init(from seed: Data32) throws(Error) {
            var ptr: OpaquePointer!

            try FFIUtils.call(seed.data) { ptrs in
                ed25519_signing_key_from_seed(ptrs[0].ptr, ptrs[0].count, &ptr)
            } onErr: { err throws(Error) in
                throw .createSigningKeyFailed(err)
            }

            self.ptr = SafePointer(ptr: ptr, free: ed25519_signing_key_free)
            publicKey = try PublicKey(signingKey: self.ptr.ptr.value)
        }

        public func sign(message: Data) throws(Error) -> Data64 {
            var output = Data(repeating: 0, count: 64)

            try FFIUtils.call(message, out: &output) { ptrs, out_buf in
                ed25519_sign(
                    ptr.ptr.value,
                    ptrs[0].ptr,
                    ptrs[0].count,
                    out_buf.ptr,
                    out_buf.count,
                )
            } onErr: { err throws(Error) in
                throw .signFailed(err)
            }

            return Data64(output)!
        }

        public var rawRepresentation: Data {
            var output = Data(repeating: 0, count: 32)

            FFIUtils.call(out: &output) { _, out_buf in
                ed25519_signing_key_to_bytes(ptr.ptr.value, out_buf.ptr, out_buf.count)
            }

            return output
        }
    }

    public final class PublicKey: PublicKeyProtocol, @unchecked Sendable {
        fileprivate let ptr: SendableOpaquePointer
        public let data: Data32

        public init(from data: Data32) throws(Error) {
            var ptr: OpaquePointer!

            try FFIUtils.call(data.data) { ptrs in
                ed25519_verification_key_from_bytes(ptrs[0].ptr, ptrs[0].count, &ptr)
            } onErr: { err throws(Error) in
                throw .createVerificationKeyFailed(err)
            }

            self.ptr = ptr.asSendable
            self.data = data
        }

        fileprivate init(signingKey: OpaquePointer) throws(Error) {
            var ptr: OpaquePointer!

            try FFIUtils.call { _ in
                ed25519_verification_key_from_signing_key(signingKey, &ptr)
            } onErr: { err throws(Error) in
                throw .createVerificationKeyFailed(err)
            }

            var data = Data(repeating: 0, count: 32)
            FFIUtils.call(out: &data) { _, out_buf in
                ed25519_verification_key_to_bytes(ptr, out_buf.ptr, out_buf.count)
            }

            self.ptr = ptr.asSendable
            self.data = Data32(data)!
        }

        deinit {
            ed25519_verification_key_free(ptr.value)
        }

        public func toHexString() -> String {
            data.toHexString()
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(data)
        }

        public convenience init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let data = try container.decode(Data32.self)
            try self.init(from: data)
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

        public func verify(signature: Data64, message: Data) -> Bool {
            var output = false

            FFIUtils.call(signature.data, message) { ptrs in
                ed25519_verify(
                    ptr.value,
                    ptrs[0].ptr,
                    ptrs[0].count,
                    ptrs[1].ptr,
                    ptrs[1].count,
                    &output,
                )
            }

            return output
        }
    }
}
