import bls
import Foundation
import TracingUtils

private let logger = Logger(label: "BLS")

public enum BLS: KeyType {
    public enum Error: Swift.Error {
        case createSecretFailed(Int)
        case createPublicKeyFailed(Int)
        case createMessageFailed(Int)
        case createSignatureFailed(Int)
        case keypairSignFailed(Int)
        case signatureVerifyFailed(Int)
        case aggregateSigsFailed(Int)
        case aggregatedVerifyFailed(Int)
        case invalidSecretKey
    }

    public final class SecretKey: SecretKeyProtocol, Sendable {
        fileprivate let keyPairPtr: SafePointer
        public let publicKey: PublicKey

        public init(from seed: Data32) throws(Error) {
            var ptr: OpaquePointer!
            try FFIUtils.call(seed.data) { ptrs in
                keypair_new(ptrs[0].ptr, ptrs[0].count, &ptr)
            } onErr: { err throws(Error) in
                throw .createSecretFailed(err)
            }

            // use SafePointer to ensure keypair is freed even `try PublicKey` throws
            keyPairPtr = SafePointer(ptr: ptr, free: keypair_free)
            publicKey = try PublicKey(keyPair: keyPairPtr.ptr.value)
        }

        public func sign(message: Data) throws(Error) -> Data {
            var output = Data(repeating: 0, count: Int(BLS_SIGNATURE_SERIALIZED_SIZE))

            try FFIUtils.call(message, out: &output) { ptrs, out_buf in
                keypair_sign(
                    keyPairPtr.ptr.value,
                    ptrs[0].ptr,
                    ptrs[0].count,
                    out_buf.ptr,
                    out_buf.count
                )
            } onErr: { err throws(Error) in
                throw .keypairSignFailed(err)
            }

            return output
        }
    }

    public final class PublicKey: PublicKeyProtocol, Sendable {
        fileprivate let ptr: SendableOpaquePointer
        public let data: Data144

        public init(data: Data144) throws(Error) {
            var ptr: OpaquePointer!
            try FFIUtils.call(data.data) { ptrs in
                public_new_from_bytes(ptrs[0].ptr, ptrs[0].count, &ptr)
            } onErr: { err throws(Error) in
                throw .createPublicKeyFailed(err)
            }
            self.ptr = ptr.asSendable
            self.data = data
        }

        fileprivate init(keyPair: OpaquePointer) throws(Error) {
            var ptr: OpaquePointer!
            try FFIUtils.call { _ in
                public_new_from_keypair(keyPair, &ptr)
            } onErr: { err throws(Error) in
                throw .createPublicKeyFailed(err)
            }

            var data = Data(repeating: 0, count: Int(BLS_PUBLICKEY_SERIALIZED_SIZE))
            FFIUtils.call(out: &data) { _, out_buf in
                public_serialize(ptr, out_buf.ptr, out_buf.count)
            }

            self.ptr = ptr.asSendable
            self.data = Data144(data)!
        }

        deinit {
            bls_public_free(ptr.value)
        }

        public convenience init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let data = try container.decode(Data144.self)
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

        public func verify(signature: Data, message: Data) throws(Error) -> Bool {
            var output = false

            try FFIUtils.call(signature, message) { ptrs in
                public_verify(
                    ptr.value,
                    ptrs[0].ptr,
                    ptrs[0].count,
                    ptrs[1].ptr,
                    ptrs[1].count,
                    &output
                )
            } onErr: { err throws(Error) in
                // no need to throw here, but still need to catch errors
                logger.debug("PublicKey.verify failed: \(err)")
            }

            return output
        }
    }

    public static func aggregateVerify(
        message: Data, signatures: [Data], publicKeys: [PublicKey]
    ) throws(Error) -> Bool {
        if signatures.count != publicKeys.count {
            return false
        }

        var keyPtrs: [OpaquePointer?] = []
        var sigPtrs: [OpaquePointer?] = []
        var msgPtr: OpaquePointer?

        defer {
            if let msgPtr {
                message_free(msgPtr)
            }
            for sigPtr in sigPtrs {
                signature_free(sigPtr)
            }
        }

        try FFIUtils.call(message) { ptrs in
            message_new_from_bytes(
                ptrs[0].ptr,
                ptrs[0].count,
                &msgPtr
            )
        } onErr: { err throws(Error) in
            throw .createMessageFailed(err)
        }

        for signature in signatures {
            var sigPtr: OpaquePointer?
            try FFIUtils.call(signature) { ptrs in
                signature_new_from_bytes(
                    ptrs[0].ptr,
                    ptrs[0].count,
                    &sigPtr
                )
            } onErr: { err throws(Error) in
                throw .createSignatureFailed(err)
            }
            sigPtrs.append(sigPtr)
        }

        keyPtrs = publicKeys.map(\.ptr.value)

        var output = false

        try FFIUtils.call { _ in
            keyPtrs.withUnsafeBufferPointer { keyPtrs in
                sigPtrs.withUnsafeBufferPointer { sigPtrs in
                    aggeregated_verify(
                        msgPtr,
                        sigPtrs.baseAddress!,
                        UInt(sigPtrs.count),
                        keyPtrs.baseAddress!,
                        UInt(keyPtrs.count),
                        &output
                    )
                }
            }
        } onErr: { err throws(Error) in
            logger.debug("aggregateVerify failed: \(err)")
        }

        return output
    }
}
