import Foundation
import msquic

typealias ConnectionCallback = @convention(c) (
    OpaquePointer?, UnsafeMutableRawPointer?, UnsafePointer<QuicConnectionEvent>?
) -> QuicStatus

typealias ServerListenerCallback = @convention(c) (
    OpaquePointer?, UnsafeMutableRawPointer?, UnsafeMutablePointer<QuicListenerEvent>?
) -> QuicStatus

public final class QuicServer {
    private var api: UnsafePointer<QuicApiTable>?
    private var registration: HQuic?
    private var configuration: HQuic?
    private var listener: HQuic?

    init() throws {
        var rawPointer: UnsafeRawPointer?
        let status: UInt32 = MsQuicOpenVersion(2, &rawPointer)

        if QuicStatus(status).isFailed {
            throw QuicError.invalidStatus(status: status.code)
        }
        guard
            let boundPointer: UnsafePointer<QuicApiTable> = rawPointer?.assumingMemoryBound(
                to: QuicApiTable.self)
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

    func start(ipAddress: String, port: UInt16) throws {
        try loadConfiguration()
        try openListener(ipAddress: ipAddress, port: port)
        print("Server started")
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
        print("QuicServer Deinit")
    }

    private static let serverListenerCallback: ServerListenerCallback = { listener, context, event in
        guard let context = context, let event = event else {
            return QuicStatusCode.notSupported.rawValue
        }
        let server = Unmanaged<QuicServer>.fromOpaque(context).takeUnretainedValue()
        return server.handleListenerEvent(listener, event)
    }

    private static let connectionCallback: ConnectionCallback = { connection, context, event in
        guard let event: UnsafePointer<QuicConnectionEvent> = event else {
            return QuicStatusCode.invalidParameter.rawValue
        }
        let server = Unmanaged<QuicServer>.fromOpaque(context!).takeUnretainedValue()
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
            // server.api?.pointee.SetCallbackHandler(
            //     stream, streamCallback,
            //     UnsafeMutableRawPointer(Unmanaged.passUnretained(server).toOpaque()))
        default:
            break
        }
        return QuicStatusCode.success.rawValue
    }

    private func handleListenerEvent(_ listener: OpaquePointer?, _ event: UnsafePointer<QuicListenerEvent>) -> QuicStatus {
        var status: QuicStatus = QuicStatusCode.success.rawValue
        switch event.pointee.Type {
        case QUIC_LISTENER_EVENT_NEW_CONNECTION:
            let connection = event.pointee.NEW_CONNECTION.Connection
            let connectionCallbackPointer = UnsafeMutablePointer<ConnectionCallback>.allocate(capacity: 1)
            connectionCallbackPointer.initialize(to: QuicServer.connectionCallback)
            api?.pointee.SetCallbackHandler(connection, connectionCallbackPointer, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
          status = (api?.pointee.ConnectionSetConfiguration(connection, configuration)).status
        default:
            break
        }
        return status;
    }

    private func handleConnectionEvent(_ connection: OpaquePointer?, _ event: UnsafePointer<QuicConnectionEvent>) {
       
    }

    static let streamCallback:
        @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?, UnsafePointer<QuicStreamEvent>?)
            -> UInt32 = { stream, context, event in
                guard let event = event else { return QuicStatusCode.invalidParameter.rawValue }

                switch event.pointee.Type {
                case QUIC_STREAM_EVENT_SEND_COMPLETE:
                    print("Stream send complete.")
                    return QuicStatusCode.success.rawValue
                case QUIC_STREAM_EVENT_RECEIVE:
                    print("Stream data received.")
                    return QuicStatusCode.success.rawValue
                case QUIC_STREAM_EVENT_PEER_SEND_SHUTDOWN:
                    print("Stream peer send shutdown.")
                    return QuicStatusCode.success.rawValue
                case QUIC_STREAM_EVENT_PEER_SEND_ABORTED:
                    print("Stream peer send aborted.")
                    return QuicStatusCode.success.rawValue
                case QUIC_STREAM_EVENT_SHUTDOWN_COMPLETE:
                    print("Stream shutdown complete.")
                    return QuicStatusCode.success.rawValue
                default:
                    return QuicStatusCode.invalidParameter.rawValue
                }
            }

}

extension QuicServer {
    private func loadConfiguration() throws {
        var settings = QUIC_SETTINGS()
        settings.IdleTimeoutMs = 1000
        settings.IsSet.IdleTimeoutMs = 1
        settings.IsSet.ServerResumptionLevel = 1
        settings.PeerBidiStreamCount = 1
        settings.IsSet.PeerBidiStreamCount = 1

        var credConfig = QUIC_CREDENTIAL_CONFIG()
        memset(&credConfig, 0, MemoryLayout.size(ofValue: credConfig))
        credConfig.Flags = QUIC_CREDENTIAL_FLAG_NONE

        // Load certificate configuration
        // Add your certificate loading logic here

        let buffer = Data("sample".utf8)
        let bufferPointer: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(
            capacity: buffer.count)
        buffer.copyBytes(to: bufferPointer, count: buffer.count)
        defer {
            free(bufferPointer)
        }
        var alpn: QuicBuffer = QuicBuffer(Length: UInt32(buffer.count), Buffer: bufferPointer)

        let status =
            (api?.pointee.ConfigurationOpen(
                registration, &alpn, 1, &settings, UInt32(MemoryLayout.size(ofValue: settings)),
                nil, &configuration)).status
        if status.isFailed {
            throw QuicError.invalidStatus(status: status.code)
        }

        let configStatus = (api?.pointee.ConfigurationLoadCredential(configuration, &credConfig))
            .status
        if configStatus.isFailed {
            throw QuicError.invalidStatus(status: configStatus.code)
        }
    }

    private func openListener(ipAddress: String, port: UInt16) throws {
        var listenerHandle: HQuic?
        let status =
            (api?.pointee.ListenerOpen(
                registration, QuicServer.serverListenerCallback,
                UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), &listenerHandle))
            .status
        if status.isFailed {
            throw QuicError.invalidStatus(status: status.code)
        }

        listener = listenerHandle

        let buffer = Data("sample".utf8)
        let bufferPointer: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(
            capacity: buffer.count)
        buffer.copyBytes(to: bufferPointer, count: buffer.count)
        defer {
            free(bufferPointer)
        }
        var alpn: QuicBuffer = QuicBuffer(Length: UInt32(buffer.count), Buffer: bufferPointer)
        var address: QUIC_ADDR = QUIC_ADDR()

        QuicAddrSetFamily(&address, QUIC_ADDRESS_FAMILY(QUIC_ADDRESS_FAMILY_UNSPEC))
        QuicAddrSetPort(&address, port)

        let startStatus = (api?.pointee.ListenerStart(listener, &alpn, 1, &address)).status

        if startStatus.isFailed {
            throw QuicError.invalidStatus(status: startStatus.code)
        }
    }
}
