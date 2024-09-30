import Foundation
import Logging
import msquic
import Utils

let logger = Logger(label: "QuicConnection")

public protocol QuicConnectionMessageHandler: AnyObject {
    func didReceiveMessage(
        connection: QuicConnection, stream: QuicStream?, message: QuicMessage
    )
    func didReceiveError(
        connection: QuicConnection, stream: QuicStream, error: QuicError
    )
}

actor StreamManager {
    private var uniquePersistentStreams: [StreamKind: QuicStream] = [:]
    private var commonEphemeralStreams: [QuicStream]

    init() {
        uniquePersistentStreams = [:]
        commonEphemeralStreams = .init()
    }

    func getUniquePersistentStream(kind: StreamKind) -> QuicStream? {
        uniquePersistentStreams[kind]
    }

    func addUniquePersistentStream(kind: StreamKind, stream: QuicStream) {
        uniquePersistentStreams[kind] = stream
    }

    func removeUniquePersistentStream(kind: StreamKind) {
        _ = uniquePersistentStreams.removeValue(forKey: kind)
    }

    func addCommonEphemeralStream(_ stream: QuicStream) {
        commonEphemeralStreams.append(stream)
    }

    func removeCommonEphemeralStream(_ stream: QuicStream) {
        stream.close()
        commonEphemeralStreams.removeAll(where: { $0 === stream })
    }

    func closeAllCommonEphemeralStreams() {
        for stream in commonEphemeralStreams {
            stream.close()
        }
        commonEphemeralStreams.removeAll()
    }

    func closeAllUniquePersistentStreams() {
        for stream in uniquePersistentStreams.values {
            stream.close()
        }
        uniquePersistentStreams.removeAll()
    }
}

public class QuicConnection: @unchecked Sendable {
    private var connection: HQuic?
    private var api: UnsafePointer<QuicApiTable>?
    private var registration: HQuic?
    private var configuration: HQuic?
    private var streamManager: StreamManager
    private weak var messageHandler: QuicConnectionMessageHandler?
    private var connectionCallback: ConnectionCallback?

    // Initializer for creating a new connection
    init(
        api: UnsafePointer<QuicApiTable>?,
        registration: HQuic?,
        configuration: HQuic?,
        messageHandler: QuicConnectionMessageHandler? = nil
    ) throws {
        self.api = api
        self.registration = registration
        self.configuration = configuration
        self.messageHandler = messageHandler
        streamManager = StreamManager()
        connectionCallback = { connection, context, event in
            QuicConnection.connectionCallback(
                connection: connection, context: context, event: event
            )
        }
        try open()
    }

    // Initializer for wrapping an existing connection
    init(
        api: UnsafePointer<QuicApiTable>?, registration: HQuic?, configuration: HQuic?,
        connection: HQuic?, messageHandler: QuicConnectionMessageHandler? = nil
    ) {
        self.api = api
        self.registration = registration
        self.configuration = configuration
        self.connection = connection
        self.messageHandler = messageHandler
        streamManager = StreamManager()
        connectionCallback = { connection, context, event in
            QuicConnection.connectionCallback(
                connection: connection, context: context, event: event
            )
        }
    }

    // Deinitializer to ensure resources are cleaned up
    deinit {
        closeSync()
    }

    nonisolated func closeSync() {
        Task { [weak self] in
            await self?.close() // Using weak self to avoid retain cycle
            logger.info("QuicConnection Deinit")
        }
    }

    // Sets the callback handler for the connection
    func setCallbackHandler() -> QuicStatus {
        guard let api, let connection, let configuration else {
            return QuicStatusCode.invalidParameter.rawValue
        }

        let callbackPointer = unsafeBitCast(
            connectionCallback, to: UnsafeMutableRawPointer?.self
        )

        api.pointee.SetCallbackHandler(
            connection,
            callbackPointer,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        return api.pointee.ConnectionSetConfiguration(connection, configuration)
    }

    // Opens the connection
    private func open() throws {
        let status =
            (api?.pointee.ConnectionOpen(
                registration,
                { connection, context, event -> QuicStatus in
                    return QuicConnection.connectionCallback(
                        connection: connection, context: context, event: event
                    )
                }, Unmanaged.passUnretained(self).toOpaque(), &connection
            )).status
        if status.isFailed {
            throw QuicError.invalidStatus(status: status.code)
        }
    }

    // Creates or retrieves a unique persistent stream
    func createOrGetUniquePersistentStream(kind: StreamKind) async throws -> QuicStream {
        if let stream = await streamManager.getUniquePersistentStream(kind: kind) {
            return stream
        }
        let stream = try QuicStream(api: api, connection: connection, kind, messageHandler: self)
        await streamManager.addUniquePersistentStream(kind: kind, stream: stream)
        return stream
    }

    // Creates a common ephemeral stream
    func createCommonEphemeralStream() async throws -> QuicStream {
        let stream: QuicStream = try QuicStream(
            api: api, connection: connection, .commonEphemeral, messageHandler: self
        )
        await streamManager.addCommonEphemeralStream(stream)
        return stream
    }

    // Removes a stream from the connection
    func removeStream(stream: QuicStream) async {
        stream.close()
        if stream.kind == .uniquePersistent {
            await streamManager.removeUniquePersistentStream(kind: stream.kind)
        } else {
            await streamManager.removeCommonEphemeralStream(stream)
        }
    }

    // Closes the connection and cleans up resources
    func close() async {
        guard connectionCallback != nil else { return }
        connectionCallback = nil
        guard messageHandler != nil else { return }
        messageHandler = nil
        await streamManager.closeAllCommonEphemeralStreams()
        await streamManager.closeAllUniquePersistentStreams()
        guard let connection else { return }
        logger.info("QuicConnection ConnectionClose")
        api?.pointee.ConnectionClose(connection)
        self.connection = nil
    }

    // Starts the connection with the specified IP address and port
    func start(ipAddress: String, port: UInt16) throws {
        let status =
            (api?.pointee.ConnectionStart(
                connection, configuration, QUIC_ADDRESS_FAMILY(QUIC_ADDRESS_FAMILY_UNSPEC),
                ipAddress, port
            )).status
        if status.isFailed {
            throw QuicError.invalidStatus(status: status.code)
        }
    }
}

extension QuicConnection {
    // Static callback function for handling connection events
    private static func connectionCallback(
        connection: HQuic?, context: UnsafeMutableRawPointer?,
        event: UnsafePointer<QuicConnectionEvent>?
    ) -> QuicStatus {
        guard let context, let event else {
            return QuicStatusCode.notSupported.rawValue
        }

        let quicConnection: QuicConnection = Unmanaged<QuicConnection>.fromOpaque(context)
            .takeUnretainedValue()
        let status: QuicStatus = QuicStatusCode.success.rawValue
        switch event.pointee.Type {
        case QUIC_CONNECTION_EVENT_CONNECTED:
            logger.info("[\(String(describing: connection))] Connected")

        case QUIC_CONNECTION_EVENT_SHUTDOWN_INITIATED_BY_TRANSPORT:
            if event.pointee.SHUTDOWN_INITIATED_BY_TRANSPORT.Status
                == QuicStatusCode.connectionIdle.rawValue
            {
                logger.info(
                    "[\(String(describing: connection))] Successfully shut down on idle."
                )
            } else {
                logger.warning(
                    " Shut down by transport, 0x\(String(format: "%x", event.pointee.SHUTDOWN_INITIATED_BY_TRANSPORT.Status))"
                )
            }

        case QUIC_CONNECTION_EVENT_SHUTDOWN_INITIATED_BY_PEER:
            logger.warning(
                " Shut down by peer, 0x\(String(format: "%llx", event.pointee.SHUTDOWN_INITIATED_BY_PEER.ErrorCode))"
            )

        case QUIC_CONNECTION_EVENT_SHUTDOWN_COMPLETE:
            logger.info("[\(String(describing: connection))] Shutdown all done")
            if event.pointee.SHUTDOWN_COMPLETE.AppCloseInProgress == 0 {
                if let messageHandler = quicConnection.messageHandler {
                    messageHandler.didReceiveMessage(
                        connection: quicConnection,
                        stream: nil,
                        message: QuicMessage(type: .shutdownComplete, data: nil)
                    )
                    quicConnection.messageHandler = nil
                }
            }

        case QUIC_CONNECTION_EVENT_RESUMPTION_TICKET_RECEIVED:
            logger.info(
                " Ticket received (\(event.pointee.RESUMPTION_TICKET_RECEIVED.ResumptionTicketLength) bytes)"
            )

        case QUIC_CONNECTION_EVENT_PEER_STREAM_STARTED:
            logger.info("[\(String(describing: connection))] Peer stream started")
            let stream = event.pointee.PEER_STREAM_STARTED.Stream
            let quicStream = QuicStream(
                api: quicConnection.api, connection: connection, stream: stream,
                messageHandler: quicConnection
            )
            quicStream.setCallbackHandler()
            Task {
                await quicConnection.streamManager.addCommonEphemeralStream(quicStream)
            }

        default:
            break
        }
        return status
    }
}

extension QuicConnection: QuicStreamMessageHandler {
    // Handles received messages from the stream
    public func didReceiveMessage(_ stream: QuicStream, message: QuicMessage) {
        switch message.type {
        case .shutdownComplete:
            Task {
                await removeStream(stream: stream)
            }
        default:
            break
        }
        messageHandler?.didReceiveMessage(connection: self, stream: stream, message: message)
    }

    // Handles errors received from the stream
    public func didReceiveError(_ stream: QuicStream, error: QuicError) {
        logger.error("Failed to receive message: \(error)")
        messageHandler?.didReceiveError(connection: self, stream: stream, error: error)
    }
}
