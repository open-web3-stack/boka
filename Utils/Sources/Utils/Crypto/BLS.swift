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
    }

    public final class SecretKey: SecretKeyProtocol, @unchecked Sendable {
        fileprivate let keyPairPtr: SendableOpaquePointer
        public let publicKey: PublicKey

        public init(from seed: Data32) throws(Error) {
            var ptr: OpaquePointer!

            try FFIUtils.call(seed.data) { ptrs in
                keypair_new(ptrs[0].ptr, ptrs[0].count, &ptr)
            } onErr: { err throws(Error) in
                throw .createSecretFailed(err)
            }

            keyPairPtr = ptr.asSendable
            publicKey = try PublicKey(keyPair: ptr)
        }

        deinit {
            keypair_free(keyPairPtr.value)
        }

        public func sign(message: Data) throws(Error) -> Data {
            var output = Data(repeating: 0, count: 160)

            try FFIUtils.call(message, out: &output) { ptrs, out_buf in
                keypair_sign(
                    keyPairPtr.value,
                    ptrs[0].ptr,
                    ptrs[0].count,
                    out_buf.ptr,
                    out_buf.count
                )
            } onErr: { err throws(Error) in
                throw .keypairSignFailed(err)
            }

            return Data(output)
        }
    }

    public final class PublicKey: PublicKeyProtocol, @unchecked Sendable {
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

            var data = Data(repeating: 0, count: 144)
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
            var output = Data(repeating: 0, count: 1)

            try FFIUtils.call(signature, message, out: &output) { ptrs, out_buf in
                public_verify(
                    ptr.value,
                    ptrs[0].ptr,
                    ptrs[0].count,
                    ptrs[1].ptr,
                    ptrs[1].count,
                    out_buf.ptr,
                    out_buf.count
                )
            } onErr: { err throws(Error) in
                if err != 2 {
                    throw .signatureVerifyFailed(err)
                }
            }

            return output[0] == 1
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

        var output = Data(repeating: 0, count: 1)

        try FFIUtils.call(out: &output) { _, out_buf in
            keyPtrs.withUnsafeBufferPointer { keyPtrs in
                sigPtrs.withUnsafeBufferPointer { sigPtrs in
                    aggeregated_verify(
                        msgPtr,
                        sigPtrs.baseAddress!,
                        UInt(sigPtrs.count),
                        keyPtrs.baseAddress!,
                        UInt(keyPtrs.count),
                        out_buf.ptr,
                        out_buf.count
                    )
                }
            }
        } onErr: { err throws(Error) in
            throw .aggregatedVerifyFailed(err)
        }

        return output[0] == 1
    }
}
