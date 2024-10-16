import Foundation
import msquic
import Utils

public final class QuicConfiguration: Sendable {
    public let registration: QuicRegistration
    private let _ptr: SendableOpaquePointer

    var ptr: OpaquePointer {
        _ptr.value
    }

    public init(registration: QuicRegistration, pkcs12: Data, alpns: [Data], client: Bool, settings: QuicSettings) throws {
        self.registration = registration

        var ptr: HQUIC?
        var settings = settings

        try alpns.withContentUnsafeBytes { alpnPtrs in
            var buffer = [QUIC_BUFFER](repeating: QUIC_BUFFER(), count: alpnPtrs.count)
            for (i, alpnPtr) in alpnPtrs.enumerated() {
                buffer[i].Length = UInt32(alpnPtr.count)
                buffer[i].Buffer = UnsafeMutablePointer(
                    mutating: alpnPtr.bindMemory(to: UInt8.self).baseAddress!
                )
            }

            try registration.api.call("ConfigurationOpen") { api in
                api.pointee.ConfigurationOpen(
                    registration.ptr, &buffer, UInt32(alpnPtrs.count), &settings, UInt32(MemoryLayout.size(ofValue: settings)), nil, &ptr
                )
            }
        }

        _ptr = ptr!.asSendable

        try pkcs12.withUnsafeBytes { pkcs12ptr in
            var cert = QUIC_CERTIFICATE_PKCS12()
            cert.Asn1Blob = pkcs12ptr.bindMemory(to: UInt8.self).baseAddress!
            cert.Asn1BlobLength = UInt32(pkcs12ptr.count)
            cert.PrivateKeyPassword = nil

            let flags = 0
                | (client ? QUIC_CREDENTIAL_FLAG_CLIENT.rawValue : 0)
                | (client ? 0 : QUIC_CREDENTIAL_FLAG_REQUIRE_CLIENT_AUTHENTICATION.rawValue)
                // we validates it ourselves
                | QUIC_CREDENTIAL_FLAG_NO_CERTIFICATE_VALIDATION.rawValue
                // we need custom validation of the certificate
                | QUIC_CREDENTIAL_FLAG_INDICATE_CERTIFICATE_RECEIVED.rawValue
                // so we don't need to deal with openssl objects
                | QUIC_CREDENTIAL_FLAG_USE_PORTABLE_CERTIFICATES.rawValue

            try withUnsafeMutablePointer(to: &cert) { certPtr in
                var credConfig = QUIC_CREDENTIAL_CONFIG(
                    Type: QUIC_CREDENTIAL_TYPE_CERTIFICATE_PKCS12,
                    Flags: QUIC_CREDENTIAL_FLAGS(flags),
                    QUIC_CREDENTIAL_CONFIG.__Unnamed_union___Anonymous_field2(
                        CertificatePkcs12: certPtr
                    ),
                    Principal: nil,
                    Reserved: nil,
                    AsyncHandler: nil,
                    AllowedCipherSuites: QUIC_ALLOWED_CIPHER_SUITE_NONE,
                    CaCertificateFile: nil
                )

                try registration.api.call("ConfigurationLoadCredential") { api in
                    api.pointee.ConfigurationLoadCredential(ptr, &credConfig)
                }
            }
        }
    }

    deinit {
        registration.api.call { api in
            api.pointee.ConfigurationClose(ptr)
        }
    }
}
