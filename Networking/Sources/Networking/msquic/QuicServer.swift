import Foundation
import Logging
import msquic
import NIO

let quicServerLogger = Logger(label: "QuicServer")

class MessageProcessor {
    func processMessage(_: QuicMessage, completion: @escaping (Data) -> Void) {
        let responseData = Data("Processed response".utf8)
        completion(responseData)
    }
}

public final class QuicServer: @unchecked Sendable, QuicConnectionDelegate {
    private var api: UnsafePointer<QuicApiTable>?
    private var registration: HQuic?
    private var configuration: HQuic?
    private var listener: HQuic?
    private let config: QuicConfig
//    public var onMessageReceived: ((Result<QuicMessage, QuicError>) -> Void)?
    public var onMessageReceived: ((Result<QuicMessage, QuicError>, @escaping (Data) -> Void) -> Void)?
    private var pendingMessages: AtomicArray<Result<QuicMessage, QuicError>> = .init()
    private var connections: AtomicArray<QuicConnection> = .init()

    init(config: QuicConfig) throws {
        self.config = config
        var rawPointer: UnsafeRawPointer?
        let status: UInt32 = MsQuicOpenVersion(2, &rawPointer)

        if QuicStatus(status).isFailed {
            throw QuicError.invalidStatus(status: status.code)
        }
        guard
            let boundPointer: UnsafePointer<QuicApiTable> = rawPointer?.assumingMemoryBound(
                to: QuicApiTable.self
            )
        else {
            throw QuicError.getApiFailed
        }

        var registrationHandle: HQuic?
        let registrationStatus = boundPointer.pointee.RegistrationOpen(nil, &registrationHandle)
        if QuicStatus(registrationStatus).isFailed {
            throw QuicError.invalidStatus(status: registrationStatus.code)
        }

        api = boundPointer
        registration = registrationHandle
    }

    func start() throws {
        try loadConfiguration()
        try openListener(ipAddress: config.ipAddress, port: config.port)
    }

    public func didReceiveMessage(connection: QuicConnection, stream: QuicStream, result: Result<QuicMessage, QuicError>) {
        switch result {
        case let .success(quicMessage):
            switch quicMessage.type {
            case .shutdownComplete:
//                connection.close()
//                connections.removeAll(where: { $0 === connection })
                break
            case .aborted:
                break
            case .unknown:
                break
            case .received:
                pendingMessages.append(result)
                processPendingMessage(connection: connection, stream: stream)
            default:
                break
            }
        case let .failure(error):
            logger.error("Failed to receive message: \(error)")
        }
    }

    private func processPendingMessage(connection _: QuicConnection, stream: QuicStream) {
        while let result = pendingMessages.popFirst() {
            onMessageReceived?(result) { responseData in
                stream.send(buffer: responseData)
            }
        }
    }

    private func openListener(ipAddress _: String, port: UInt16) throws {
        var listenerHandle: HQuic?
        let status =
            (api?.pointee.ListenerOpen(
                registration,
                { listener, context, event -> QuicStatus in
                    QuicServer.serverListenerCallback(
                        listener: listener, context: context, event: event
                    )
                },
                UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), &listenerHandle
            ))
            .status
        if status.isFailed {
            throw QuicError.invalidStatus(status: status.code)
        }

        listener = listenerHandle

        let buffer = Data(config.alpn.utf8)
        let bufferPointer = UnsafeMutablePointer<UInt8>.allocate(
            capacity: buffer.count
        )
        buffer.copyBytes(to: bufferPointer, count: buffer.count)
        defer {
            free(bufferPointer)
        }
        var alpn = QuicBuffer(Length: UInt32(buffer.count), Buffer: bufferPointer)
        var address = QUIC_ADDR()

        QuicAddrSetFamily(&address, QUIC_ADDRESS_FAMILY(QUIC_ADDRESS_FAMILY_UNSPEC))
        QuicAddrSetPort(&address, port)
        let startStatus: QuicStatus = (api?.pointee.ListenerStart(listener, &alpn, 1, &address))
            .status

        if startStatus.isFailed {
            throw QuicError.invalidStatus(status: startStatus.code)
        }
    }

    private static func serverListenerCallback(
        listener _: HQuic?, context: UnsafeMutableRawPointer?,
        event: UnsafePointer<QUIC_LISTENER_EVENT>?
    ) -> QuicStatus {
        var status: QuicStatus = QuicStatusCode.notSupported.rawValue
        guard let context, let event else {
            return status
        }
        let server: QuicServer = Unmanaged<QuicServer>.fromOpaque(context).takeUnretainedValue()

        switch event.pointee.Type {
        case QUIC_LISTENER_EVENT_NEW_CONNECTION:
            let connection: HQuic = event.pointee.NEW_CONNECTION.Connection
            guard let api = server.api else {
                return status
            }

            let connectionHandler = QuicConnection(
                api: api,
                registration: connection,
                configuration: server.registration,
                connection: server.configuration
            )
            connectionHandler.delegate = server
            server.connections.append(connectionHandler)
            status = connectionHandler.setCallbackHandler()

        default:
            break
        }
        return status
    }

    deinit {
        if listener != nil {
            api?.pointee.ListenerClose(listener)
            listener = nil
        }
        if configuration != nil {
            api?.pointee.ConfigurationClose(configuration)
            configuration = nil
        }
        if registration != nil {
            api?.pointee.RegistrationClose(registration)
            registration = nil
        }
        MsQuicClose(api)
    }
}

extension QuicServer {
    private func loadConfiguration() throws {
        var settings = QUIC_SETTINGS()
        settings.IdleTimeoutMs = 30000
        settings.IsSet.IdleTimeoutMs = 1
        settings.ServerResumptionLevel = 2 // QUIC_SERVER_RESUME_AND_ZERORTT
        settings.IsSet.ServerResumptionLevel = 1
        settings.PeerBidiStreamCount = 1
        settings.IsSet.PeerBidiStreamCount = 1
        var certificateFile = QUIC_CERTIFICATE_FILE()
        var credConfig = QUIC_CREDENTIAL_CONFIG()

        memset(&certificateFile, 0, MemoryLayout.size(ofValue: certificateFile))
        memset(&credConfig, 0, MemoryLayout.size(ofValue: credConfig))

        let certCString = config.cert.utf8CString
        let keyFileCString = config.key.utf8CString

        let certPointer = UnsafeMutablePointer<CChar>.allocate(capacity: certCString.count)
        let keyFilePointer = UnsafeMutablePointer<CChar>.allocate(capacity: keyFileCString.count)
        // Copy the C strings to the pointers
        certCString.withUnsafeBytes {
            certPointer.initialize(
                from: $0.bindMemory(to: CChar.self).baseAddress!, count: certCString.count
            )
        }

        keyFileCString.withUnsafeBytes {
            keyFilePointer.initialize(
                from: $0.bindMemory(to: CChar.self).baseAddress!, count: keyFileCString.count
            )
        }

        certificateFile.CertificateFile = UnsafePointer(certPointer)
        certificateFile.PrivateKeyFile = UnsafePointer(keyFilePointer)

        let certificateFilePointer =
            UnsafeMutablePointer<QUIC_CERTIFICATE_FILE>.allocate(capacity: 1)
        certificateFilePointer.initialize(to: certificateFile)
        credConfig.Type = QUIC_CREDENTIAL_TYPE_CERTIFICATE_FILE
        credConfig.Flags = QUIC_CREDENTIAL_FLAG_NONE
        credConfig.CertificateFile = certificateFilePointer

        let buffer = Data(config.alpn.utf8)
        let bufferPointer = UnsafeMutablePointer<UInt8>.allocate(
            capacity: buffer.count
        )
        buffer.copyBytes(to: bufferPointer, count: buffer.count)

        defer {
            certPointer.deallocate()
            keyFilePointer.deallocate()
            bufferPointer.deallocate()
        }

        var alpn = QuicBuffer(Length: UInt32(buffer.count), Buffer: bufferPointer)

        let status =
            (api?.pointee.ConfigurationOpen(
                registration, &alpn, 1, &settings, UInt32(MemoryLayout.size(ofValue: settings)),
                nil, &configuration
            )).status
        if status.isFailed {
            throw QuicError.invalidStatus(status: status.code)
        }

        let configStatus = (api?.pointee.ConfigurationLoadCredential(configuration, &credConfig))
            .status
        if configStatus.isFailed {
            throw QuicError.invalidStatus(status: configStatus.code)
        }
    }
}
