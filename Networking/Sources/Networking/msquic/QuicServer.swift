import Foundation
import Logging
import msquic
import NIO

let quicServerLogger = Logger(label: "QuicServer")

public final class QuicServer {
    private var api: UnsafePointer<QuicApiTable>?
    private var registration: HQuic?
    private var configuration: HQuic?
    private var listener: HQuic?
    private let streamCallback: StreamCallback
    private let connectionCallback: ConnectionCallback
    public var onMessageReceived: ((Result<QuicMessage, QuicError>) -> Void)?
    private let config: QuicConfig

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
        streamCallback = { stream, context, event in
            QuicServer.streamCallback(
                stream: stream, context: context, event: event
            )
        }
        connectionCallback = { connection, context, event in
            QuicServer.connectionCallback(
                connection: connection, context: context, event: event
            )
        }
    }

    func start() throws {
        try loadConfiguration()
        try openListener(ipAddress: config.ipAddress, port: config.port)
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

            let callbackPointer = unsafeBitCast(
                server.connectionCallback, to: UnsafeMutableRawPointer?.self
            )

            api.pointee.SetCallbackHandler(
                connection,
                callbackPointer,
                UnsafeMutableRawPointer(Unmanaged.passUnretained(server).toOpaque())
            )

            status = api.pointee.ConnectionSetConfiguration(
                connection, server.configuration
            )

        default:
            break
        }
        return status
    }

    private func sendBuffer(stream: HQuic?, buffer: Data) -> QuicStatus {
        let messageLength = buffer.count

        let sendBufferRaw = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<QUIC_BUFFER>.size + messageLength,
            alignment: MemoryLayout<QUIC_BUFFER>.alignment
        )

        let sendBuffer = sendBufferRaw.assumingMemoryBound(to: QUIC_BUFFER.self)
        let bufferPointer = UnsafeMutablePointer<UInt8>.allocate(
            capacity: messageLength
        )
        buffer.copyBytes(to: bufferPointer, count: messageLength)

        sendBuffer.pointee.Buffer = bufferPointer
        sendBuffer.pointee.Length = UInt32(messageLength)

        var status = QuicStatusCode.success.rawValue
        status =
            (api?.pointee.StreamSend(stream, sendBuffer, 1, QUIC_SEND_FLAG_FIN, sendBufferRaw))
                .status
        return status
    }

    private static func streamCallback(
        stream: HQuic?, context: UnsafeMutableRawPointer?, event: UnsafePointer<QUIC_STREAM_EVENT>?
    ) -> QuicStatus {
        guard let context, let event else {
            return QuicStatusCode.notSupported.rawValue
        }
        let server = Unmanaged<QuicServer>.fromOpaque(context).takeUnretainedValue()
        var status: QuicStatus = QuicStatusCode.success.rawValue
        switch event.pointee.Type {
        case QUIC_STREAM_EVENT_SEND_COMPLETE:
            if let clientContext = event.pointee.SEND_COMPLETE.ClientContext {
                free(clientContext)
            }
            logger.info("[strm][\(String(describing: stream))] Data sent")
        case QUIC_STREAM_EVENT_RECEIVE:
            logger.info("[strm][\(String(describing: stream))] Data Received")

            let bufferCount = event.pointee.RECEIVE.BufferCount
            let buffers: UnsafePointer<QuicBuffer> = event.pointee.RECEIVE.Buffers
            var buffersData = Data()
            for i in 0 ..< bufferCount {
                let buffer = buffers[Int(i)]
                let bufferLength = Int(buffer.Length)
                let bufferData = Data(bytes: buffer.Buffer, count: bufferLength)
                buffersData.append(bufferData)
                logger.info(
                    "[strm] Data length \(bufferLength) bytes: \(String([UInt8](bufferData).map { Character(UnicodeScalar($0)) }))"
                )
            }
            server.onMessageReceived?(.success(QuicMessage(type: .received, data: buffersData)))
        case QUIC_STREAM_EVENT_PEER_SEND_SHUTDOWN:
            logger.info("[strm][\(String(describing: stream))] Peer shut down")
        case QUIC_STREAM_EVENT_PEER_SEND_ABORTED:
            logger.info("[strm][\(String(describing: stream))] Peer aborted")
            status =
                (server.api?.pointee.StreamShutdown(stream, QUIC_STREAM_SHUTDOWN_FLAG_ABORT, 0))
                    .status
        case QUIC_STREAM_EVENT_SHUTDOWN_COMPLETE:
            logger.info("[strm][\(String(describing: stream))] All done")
            if event.pointee.SHUTDOWN_COMPLETE.AppCloseInProgress == 0 {
                server.api?.pointee.StreamClose(stream)
                server.onMessageReceived?(.success(QuicMessage(type: .shutdown, data: nil)))
            }
        default:
            break
        }
        return status
    }

    private static func connectionCallback(
        connection _: HQuic?, context: UnsafeMutableRawPointer?,
        event: UnsafePointer<QUIC_CONNECTION_EVENT>?
    ) -> QuicStatus {
        guard let context: UnsafeMutableRawPointer, let event else {
            return QuicStatusCode.notSupported.rawValue
        }
        let server: QuicServer = Unmanaged<QuicServer>.fromOpaque(context).takeUnretainedValue()
        switch event.pointee.Type {
        case QUIC_CONNECTION_EVENT_CONNECTED:
            logger.info("Connected")
        case QUIC_CONNECTION_EVENT_SHUTDOWN_INITIATED_BY_TRANSPORT:
            logger.info("Connection shutdown initiated by transport.")
        case QUIC_CONNECTION_EVENT_SHUTDOWN_INITIATED_BY_PEER:
            logger.info("Connection shutdown initiated by peer.")
        case QUIC_CONNECTION_EVENT_SHUTDOWN_COMPLETE:
            logger.info("Connection shutdown complete.")
        case QUIC_CONNECTION_EVENT_PEER_STREAM_STARTED:
            let stream = event.pointee.PEER_STREAM_STARTED.Stream
            let callbackPointer = unsafeBitCast(
                server.streamCallback, to: UnsafeMutableRawPointer.self
            )

            server.api?.pointee.SetCallbackHandler(
                stream, callbackPointer,
                UnsafeMutableRawPointer(Unmanaged.passUnretained(server).toOpaque())
            )
        default:
            break
        }
        return QuicStatusCode.success.rawValue
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
}
