import Foundation
import Logging
import msquic

let listenLogger: Logger = .init(label: "QuicListener")

public protocol QuicListenerMessageHandler: AnyObject {
    func didReceiveMessage(connection: QuicConnection, stream: QuicStream, message: QuicMessage)
    func didReceiveError(connection: QuicConnection, stream: QuicStream, error: QuicError)
}

public class QuicListener {
    private var api: UnsafePointer<QuicApiTable>?
    private var registration: HQuic?
    private var configuration: HQuic?
    private var config: QuicConfig
    private var listener: HQuic?
    private var connections: AtomicArray<QuicConnection> = .init()
    public weak var messageHandler: QuicListenerMessageHandler?

    public init(
        api: UnsafePointer<QuicApiTable>?,
        registration: HQuic?,
        configuration: HQuic?,
        config: QuicConfig,
        messageHandler: QuicListenerMessageHandler? = nil
    ) {
        self.api = api
        self.registration = registration
        self.configuration = configuration
        self.config = config
        self.messageHandler = messageHandler
    }

    public func openListener(port: UInt16) throws {
        var listenerHandle: HQuic?
        let status = (api?.pointee.ListenerOpen(
            registration,
            { listener, context, event -> QuicStatus in
                QuicListener.serverListenerCallback(
                    listener: listener, context: context, event: event
                )
            },
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), &listenerHandle
        )).status

        if status.isFailed {
            throw QuicError.invalidStatus(status: status.code)
        }

        listener = listenerHandle

        let buffer = Data(config.alpn.utf8)
        let bufferPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: buffer.count)
        buffer.copyBytes(to: bufferPointer, count: buffer.count)
        defer {
            free(bufferPointer)
        }
        var alpn = QuicBuffer(Length: UInt32(buffer.count), Buffer: bufferPointer)
        var address = QUIC_ADDR()

        QuicAddrSetFamily(&address, QUIC_ADDRESS_FAMILY(QUIC_ADDRESS_FAMILY_UNSPEC))
        QuicAddrSetPort(&address, port)
        let startStatus: QuicStatus = (api?.pointee.ListenerStart(listener, &alpn, 1, &address)).status

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
        let listener: QuicListener = Unmanaged<QuicListener>.fromOpaque(context).takeUnretainedValue()
        listenLogger.info("Server listener callback type \(event.pointee.Type.rawValue)")
        switch event.pointee.Type {
        case QUIC_LISTENER_EVENT_NEW_CONNECTION:
            listenLogger.info("New connection")
            let connection: HQuic = event.pointee.NEW_CONNECTION.Connection
            guard let api = listener.api else {
                return status
            }

            let quicConnection = QuicConnection(
                api: api,
                registration: listener.registration,
                configuration: listener.configuration,
                connection: connection,
                messageHandler: listener
            )
            listener.connections.append(quicConnection)
            status = quicConnection.setCallbackHandler()

        default:
            break
        }
        return status
    }

    public func close() {
        if let listener {
            api?.pointee.ListenerClose(listener)
            self.listener = nil
        }
        closeAllConnections()
    }

    private func closeAllConnections() {
        for connection in connections {
            connection.close()
        }
        connections.removeAll()
    }
}

extension QuicListener: QuicConnectionMessageHandler {
    public func didReceiveMessage(
        connection: QuicConnection, stream: QuicStream?, message: QuicMessage
    ) {
        switch message.type {
        case .shutdownComplete:
            listenLogger.info("Connection shutdown complete")
            removeConnection(connection)
        case .received:
            if let stream {
                messageHandler?.didReceiveMessage(connection: connection, stream: stream, message: message)
            }
        default:
            break
        }
    }

    public func didReceiveError(
        connection: QuicConnection, stream: QuicStream, error: QuicError
    ) {
        listenLogger.error("Failed to receive message: \(error)")
        messageHandler?.didReceiveError(connection: connection, stream: stream, error: error)
    }

    private func removeConnection(_ connection: QuicConnection) {
        connection.close()
        connections.removeAll(where: { $0 === connection })
    }
}
