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

        public func sign(message: Data) throws(Error) -> Data96 {
            var output = Data(repeating: 0, count: 96)

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

            return Data96(Data(output))!
        }
    }

    public final class PublicKey: PublicKeyProtocol, @unchecked Sendable {
        fileprivate let ptr: SendableOpaquePointer
        public let data: Data144

        public init(data: Data144) throws(Error) {
            var ptr: OpaquePointer!
            try FFIUtils.call(data.data) { ptrs in
                public_new_from_data(ptrs[0].ptr, ptrs[0].count, &ptr)
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
            public_free(ptr.value)
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

        public func verify(signature: Data96, message: Data) throws(Error) -> Bool {
            var output = Data(repeating: 0, count: 1)

            try FFIUtils.call(signature.data, message, out: &output) { ptrs, out_buf in
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
                throw .signatureVerifyFailed(err)
            }

            return output[0] == 1
        }
    }

    public static func aggregateVerify(
        signatures: [Data96], messages: [Data], publicKeys: [PublicKey]
    ) throws(Error) -> Bool {
        if messages.count != publicKeys.count {
            return false
        }

        var msgPtrs: [OpaquePointer?] = []
        var keyPtrs: [OpaquePointer?] = []
        var sigPtrs: [OpaquePointer?] = []

        defer {
            for msgPtr in msgPtrs {
                message_free(msgPtr)
            }
            for sigPtr in sigPtrs {
                signature_free(sigPtr)
            }
            // do not free public keys here as they're owned externally
        }

        for msg in messages {
            var msgPtr: OpaquePointer?
            try FFIUtils.call(msg) { ptrs in
                message_new_from_bytes(
                    ptrs[0].ptr,
                    ptrs[0].count,
                    &msgPtr
                )
            } onErr: { err throws(Error) in
                throw .createMessageFailed(err)
            }
            msgPtrs.append(msgPtr)
        }
        for signature in signatures {
            var sigPtr: OpaquePointer?
            try FFIUtils.call(signature.data) { ptrs in
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
            msgPtrs.withUnsafeBufferPointer { msgPtrs in
                keyPtrs.withUnsafeBufferPointer { keyPtrs in
                    sigPtrs.withUnsafeBufferPointer { sigPtrs in
                        aggeregated_verify(
                            sigPtrs.baseAddress,
                            UInt(sigPtrs.count),
                            msgPtrs.baseAddress,
                            UInt(msgPtrs.count),
                            keyPtrs.baseAddress,
                            UInt(keyPtrs.count),
                            out_buf.ptr,
                            out_buf.count
                        )
                    }
                }
            }
        } onErr: { err throws(Error) in
            throw .aggregatedVerifyFailed(err)
        }

        return output[0] == 1
    }

    // TODO: maybe we don't need this method
    public static func aggregateSignatures(signatures: [Data96]) throws -> Data96 {
        let sigPtrs: [OpaquePointer?] = []
        defer {
            for sigPtr in sigPtrs {
                signature_free(sigPtr)
            }
        }

        for signature in signatures {
            var sigPtr: OpaquePointer?
            try FFIUtils.call(signature.data) { ptrs in
                signature_new_from_bytes(
                    ptrs[0].ptr,
                    ptrs[0].count,
                    &sigPtr
                )
            } onErr: { err throws(Error) in
                throw .createSignatureFailed(err)
            }
        }

        var output = Data(repeating: 0, count: 96)

        try FFIUtils.call(out: &output) { _, out_buf in
            sigPtrs.withUnsafeBufferPointer { sigPtrs in
                aggregate_signatures(
                    sigPtrs.baseAddress,
                    UInt(sigPtrs.count),
                    out_buf.ptr,
                    out_buf.count
                )
            }
        } onErr: { err throws(Error) in
            throw .aggregateSigsFailed(err)
        }

        return Data96(Data(output))!
    }
}
