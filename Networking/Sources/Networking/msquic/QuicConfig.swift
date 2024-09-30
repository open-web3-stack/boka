import Foundation
import msquic

public struct QuicConfig {
    public let id: String
    public let cert: String
    public let key: String
    public let alpn: String
    public let ipAddress: String
    public let port: UInt16

    public func loadConfiguration(
        api: UnsafePointer<QuicApiTable>?,
        registration: HQuic?,
        configuration: inout HQuic?
    ) throws {
        // Initialize QUIC settings
        var settings = QuicSettings()
        settings.IdleTimeoutMs = 30000
        settings.IsSet.IdleTimeoutMs = 1
        settings.ServerResumptionLevel = 2 // QUIC_SERVER_RESUME_AND_ZERORTT
        settings.IsSet.ServerResumptionLevel = 1
        settings.PeerBidiStreamCount = 1
        settings.IsSet.PeerBidiStreamCount = 1

        // Use withCString to avoid manual memory management
        try cert.withCString { certPointer in
            try key.withCString { keyPointer in
                var certificateFile = QuicCertificateFile(
                    PrivateKeyFile: keyPointer, CertificateFile: certPointer
                )

                // Use withUnsafeMutablePointer to ensure the pointer is valid
                try withUnsafeMutablePointer(to: &certificateFile) { certFilePointer in
                    var credConfig = QuicCredentialConfig(
                        Type: QUIC_CREDENTIAL_TYPE_CERTIFICATE_FILE,
                        Flags: QUIC_CREDENTIAL_FLAG_NONE,
                        QuicCredentialConfig.__Unnamed_union___Anonymous_field2(
                            CertificateFile: certFilePointer
                        ),
                        Principal: nil, // Not needed in this context
                        Reserved: nil, // Not needed in this context
                        AsyncHandler: nil, // Not needed in this context
                        AllowedCipherSuites: QUIC_ALLOWED_CIPHER_SUITE_NONE, // Default value
                        CaCertificateFile: nil // Not needed in this context
                    )

                    // Convert ALPN to data buffer
                    let buffer = Data(alpn.utf8)
                    try buffer.withUnsafeBytes { bufferPointer in
                        var alpnBuffer = QUIC_BUFFER(
                            Length: UInt32(buffer.count),
                            Buffer: UnsafeMutablePointer(
                                mutating: bufferPointer.bindMemory(to: UInt8.self).baseAddress!
                            )
                        )

                        // Open QUIC configuration
                        let status = (api?.pointee.ConfigurationOpen(
                            registration, &alpnBuffer, 1, &settings, UInt32(MemoryLayout.size(ofValue: settings)),
                            nil, &configuration
                        )).status

                        if status.isFailed {
                            throw QuicError.invalidStatus(status: status.code)
                        }

                        // Load credentials into the configuration
                        let configStatus = (api?.pointee.ConfigurationLoadCredential(configuration, &credConfig)).status
                        if configStatus.isFailed {
                            throw QuicError.invalidStatus(status: configStatus.code)
                        }
                    }
                }
            }
        }
    }
}
