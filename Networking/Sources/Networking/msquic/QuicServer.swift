import Foundation
import msquic
import NIO

public final class QuicServer {
    private var api: UnsafePointer<QuicApiTable>?
    private var registration: HQuic?
    private var configuration: HQuic?

    private var listener: HQuic?
    private var group: MultiThreadedEventLoopGroup?

    init() throws {
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
        group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    }

    func start(ipAddress: String, port: UInt16) throws {
        try loadConfiguration()
        try openListener(ipAddress: ipAddress, port: port)
        try group?.next().scheduleTask(in: .hours(1)) {}.futureResult.wait()
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
        try? group?.syncShutdownGracefully()
    }

    private static let serverListenerCallback: ServerListenerCallback = {
        _, context, event in
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
                QuicServer.connectionCallback, to: UnsafeMutableRawPointer.self
            )

            api.pointee.SetCallbackHandler(
                connection,
                callbackPointer,
                UnsafeMutableRawPointer(Unmanaged.passUnretained(server).toOpaque())
            )

            let connectStatus = api.pointee.ConnectionSetConfiguration(
                connection, server.configuration
            )
            // c unsigned int  < 0  pending
            let signedStatus = Int32(bitPattern: connectStatus)
            print("ConnectionSetConfiguration status:", signedStatus)
            status = connectStatus
        default:
            break
        }
        return status
    }

    private static let streamCallback: StreamCallback = { stream, context, event in
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
            print("[strm][\(String(describing: stream))] Data sent")
        case QUIC_STREAM_EVENT_RECEIVE:
            let bufferCount = event.pointee.RECEIVE.BufferCount
            let buffers: UnsafePointer<QuicBuffer>? = event.pointee.RECEIVE.Buffers
            // Sends the buffer over the stream. Note the FIN flag is passed along with
            // the buffer. This indicates this is the last buffer on the stream and the
            // the stream is shut down (in the send direction) immediately after.
            status =
                (server.api?.pointee.StreamSend(
                    stream, buffers, bufferCount, QUIC_SEND_FLAG_FIN, nil
                ))
                .status
            if status.isFailed {
                let shutdown =
                    (server.api?.pointee.StreamShutdown(stream, QUIC_STREAM_SHUTDOWN_FLAG_ABORT, 0))
                        .status
                if shutdown.isFailed {
                    print("StreamShutdown failed, 0x\(String(format: "%x", shutdown))!")
                    return QuicStatusCode.internalError.rawValue
                }
            }
        case QUIC_STREAM_EVENT_PEER_SEND_SHUTDOWN:
            print("[strm][\(String(describing: stream))] Peer shut down")
        case QUIC_STREAM_EVENT_PEER_SEND_ABORTED:
            print("[strm][\(String(describing: stream))] Peer aborted")
            status =
                (server.api?.pointee.StreamShutdown(stream, QUIC_STREAM_SHUTDOWN_FLAG_ABORT, 0))
                    .status
        case QUIC_STREAM_EVENT_SHUTDOWN_COMPLETE:
            print("[strm][\(String(describing: stream))] All done")
            if event.pointee.SHUTDOWN_COMPLETE.AppCloseInProgress == 0 {
                server.api?.pointee.StreamClose(stream)
            }
        default:
            break
        }
        return status
    }

    private static let connectionCallback: ConnectionCallback = { _, context, event in

        guard let context: UnsafeMutableRawPointer, let event else {
            return QuicStatusCode.notSupported.rawValue
        }
        let server: QuicServer = Unmanaged<QuicServer>.fromOpaque(context).takeUnretainedValue()
        switch event.pointee.Type {
        case QUIC_CONNECTION_EVENT_CONNECTED:
            print("Connected")
        case QUIC_CONNECTION_EVENT_SHUTDOWN_INITIATED_BY_TRANSPORT:
            print("Connection shutdown initiated by transport.")
        case QUIC_CONNECTION_EVENT_SHUTDOWN_INITIATED_BY_PEER:
            print("Connection shutdown initiated by peer.")
        case QUIC_CONNECTION_EVENT_SHUTDOWN_COMPLETE:
            print("Connection shutdown complete.")
        case QUIC_CONNECTION_EVENT_PEER_STREAM_STARTED:
            let stream = event.pointee.PEER_STREAM_STARTED.Stream
            let callbackPointer = unsafeBitCast(
                QuicServer.streamCallback, to: UnsafeMutableRawPointer.self
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
        settings.IdleTimeoutMs = 1000
        settings.IsSet.IdleTimeoutMs = 1
        settings.ServerResumptionLevel = 2 // QUIC_SERVER_RESUME_AND_ZERORTT
        settings.IsSet.ServerResumptionLevel = 1
        settings.PeerBidiStreamCount = 1
        settings.IsSet.PeerBidiStreamCount = 1
        var certificateFile = QUIC_CERTIFICATE_FILE()
        var credConfig = QUIC_CREDENTIAL_CONFIG()

        memset(&certificateFile, 0, MemoryLayout.size(ofValue: certificateFile))
        memset(&credConfig, 0, MemoryLayout.size(ofValue: credConfig))
        let currentPath = FileManager.default.currentDirectoryPath

        let cert = currentPath + "/Sources/assets/server.cert"
        let keyFile = currentPath + "/Sources/assets/server.key"
        print("cert: \(cert)")
        print("keyFile: \(keyFile)")
//        let cert = "/Users/mackun/boka/Networking/Sources/assets/server.cert"
//        let keyFile = "/Users/mackun/boka/Networking/Sources/assets/server.key"
        let certCString = cert.utf8CString
        let keyFileCString = keyFile.utf8CString

        let certPointer = UnsafeMutablePointer<CChar>.allocate(capacity: certCString.count)
        let keyFilePointer = UnsafeMutablePointer<CChar>.allocate(capacity: keyFileCString.count)

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

        let buffer = Data("sample".utf8)
        let bufferPointer = UnsafeMutablePointer<UInt8>.allocate(
            capacity: buffer.count
        )
        buffer.copyBytes(to: bufferPointer, count: buffer.count)
        defer {
            free(bufferPointer)
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
        // Create/allocate a new listener object.
        let status =
            (api?.pointee.ListenerOpen(
                registration, QuicServer.serverListenerCallback,
                UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), &listenerHandle
            ))
            .status
        if status.isFailed {
            throw QuicError.invalidStatus(status: status.code)
        }

        listener = listenerHandle

        let buffer = Data("sample".utf8)
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
        // Starts listening for incoming connections.
        let startStatus: QuicStatus = (api?.pointee.ListenerStart(listener, &alpn, 1, &address))
            .status

        if startStatus.isFailed {
            throw QuicError.invalidStatus(status: startStatus.code)
        }
    }
}
