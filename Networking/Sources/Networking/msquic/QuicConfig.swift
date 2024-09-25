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
        registration: HQuic?
    ) throws -> HQuic? {
        // Initialize QUIC settings
        var settings = QuicSettings()
        settings.IdleTimeoutMs = 10000
        settings.IsSet.IdleTimeoutMs = 1
        settings.ServerResumptionLevel = 2 // QUIC_SERVER_RESUME_AND_ZERORTT
        settings.IsSet.ServerResumptionLevel = 1
        settings.PeerBidiStreamCount = 1
        settings.IsSet.PeerBidiStreamCount = 1

        // Initialize certificate and credential configurations
        var certificateFile = QuicCertificateFile()
        var credConfig = QuicCredentialConfig()

        memset(&certificateFile, 0, MemoryLayout.size(ofValue: certificateFile))
        memset(&credConfig, 0, MemoryLayout.size(ofValue: credConfig))

        // Convert certificate and key paths to C strings
        let certCString = cert.utf8CString
        let keyFileCString = key.utf8CString

        // Allocate memory for certificate and key paths
        let certPointer = UnsafeMutablePointer<CChar>.allocate(capacity: certCString.count)
        let keyFilePointer = UnsafeMutablePointer<CChar>.allocate(capacity: keyFileCString.count)

        // Copy the C strings to the allocated memory
        let certBufferPointer = UnsafeMutableBufferPointer(start: certPointer, count: certCString.count)
        _ = certBufferPointer.initialize(from: certCString)

        let keyFileBufferPointer = UnsafeMutableBufferPointer(start: keyFilePointer, count: keyFileCString.count)
        _ = keyFileBufferPointer.initialize(from: keyFileCString)

        // Set certificate file paths in QUIC_CERTIFICATE_FILE
        certificateFile.CertificateFile = UnsafePointer(certPointer)
        certificateFile.PrivateKeyFile = UnsafePointer(keyFilePointer)

        let certificateFilePointer = UnsafeMutablePointer<QUIC_CERTIFICATE_FILE>.allocate(capacity: 1)
        certificateFilePointer.initialize(to: certificateFile)

        // Configure credentials
        credConfig.Type = QUIC_CREDENTIAL_TYPE_CERTIFICATE_FILE
        credConfig.Flags = QUIC_CREDENTIAL_FLAG_NONE
        credConfig.CertificateFile = certificateFilePointer

        // Convert ALPN to data buffer
        let buffer = Data(alpn.utf8)
        let bufferPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: buffer.count)
        buffer.copyBytes(to: bufferPointer, count: buffer.count)

        // Ensure memory is deallocated
        defer {
            certPointer.deallocate()
            keyFilePointer.deallocate()
            certificateFilePointer.deallocate()
            bufferPointer.deallocate()
        }

        var alpn = QuicBuffer(Length: UInt32(buffer.count), Buffer: bufferPointer)

        // Open QUIC configuration
        var configuration: HQuic?
        let status = (api?.pointee.ConfigurationOpen(
            registration, &alpn, 1, &settings, UInt32(MemoryLayout.size(ofValue: settings)),
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

        return configuration
    }
}
