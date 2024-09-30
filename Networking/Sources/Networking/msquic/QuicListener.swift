import Foundation
import Logging
import msquic
import Utils

let listenLogger: Logger = .init(label: "QuicListener")

public protocol QuicListenerMessageHandler: AnyObject {
    func didReceiveMessage(connection: QuicConnection, stream: QuicStream, message: QuicMessage)
        async
    func didReceiveError(connection: QuicConnection, stream: QuicStream, error: QuicError) async
}

public class QuicListener: @unchecked Sendable {
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
        messageHandler: QuicServer? = nil
    ) throws {
        self.api = api
        self.registration = registration
        self.configuration = configuration
        self.config = config
        self.messageHandler = messageHandler
        try openListener(port: config.port, listener: &listener)
    }

    deinit {
        listenLogger.trace("QuicListener Deinit")
    }

    private func openListener(port: UInt16, listener: inout HQuic?) throws {
        // Open the listener
        let status =
            (api?.pointee.ListenerOpen(
                registration,
                { listener, context, event -> QuicStatus in
                    QuicListener.serverListenerCallback(
                        listener: listener, context: context, event: event
                    )
                },
                UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), &listener
            )).status

        guard status.isSucceeded else {
            throw QuicError.invalidStatus(status: status.code)
        }

        // Prepare ALPN buffer
        let alpnData = Data(config.alpn.utf8)
        try alpnData.withUnsafeBytes { bufferPointer in
            var alpnBuffer = QuicBuffer(
                Length: UInt32(bufferPointer.count),
                Buffer: UnsafeMutablePointer(
                    mutating: bufferPointer.bindMemory(to: UInt8.self).baseAddress!
                )
            )

            // Prepare address
            var address = QUIC_ADDR()
            QuicAddrSetFamily(&address, QUIC_ADDRESS_FAMILY(QUIC_ADDRESS_FAMILY_UNSPEC))
            QuicAddrSetPort(&address, port)

            // Start the listener
            let startStatus: QuicStatus =
                (api?.pointee.ListenerStart(listener, &alpnBuffer, 1, &address)).status

            guard startStatus.isSucceeded else {
                throw QuicError.invalidStatus(status: startStatus.code)
            }
        }
    }

    func getNetAddr() -> NetAddr {
        NetAddr(ipAddress: config.ipAddress, port: config.port)
    }

    private static func serverListenerCallback(
        listener _: HQuic?, context: UnsafeMutableRawPointer?,
        event: UnsafePointer<QUIC_LISTENER_EVENT>?
    ) -> QuicStatus {
        var status: QuicStatus = QuicStatusCode.notSupported.rawValue
        guard let context, let event else {
            return status
        }
        let listener: QuicListener = Unmanaged<QuicListener>.fromOpaque(context)
            .takeUnretainedValue()
        switch event.pointee.Type {
        case QUIC_LISTENER_EVENT_NEW_CONNECTION:
            listenLogger.debug("New connection")
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
            Task {
                await connection.close()
            }
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
            removeConnection(connection)
        case .received:
            if let stream, let messageHandler {
                Task {
                    await messageHandler.didReceiveMessage(
                        connection: connection, stream: stream, message: message
                    )
                }
            }
        default:
            break
        }
    }

    public func didReceiveError(
        connection: QuicConnection, stream: QuicStream, error: QuicError
    ) {
        listenLogger.error("Failed to receive message: \(error)")
        if let messageHandler {
            Task {
                await messageHandler.didReceiveError(
                    connection: connection, stream: stream, error: error
                )
            }
        }
    }

    private func removeConnection(_ connection: QuicConnection) {
        connection.closeSync()
        connections.removeAll(where: { $0 === connection })
    }
}
