import Foundation
import Logging
import msquic
import Utils

let logger = Logger(label: "QuicConnection")

public protocol QuicConnectionMessageHandler: AnyObject {
    func didReceiveMessage(
        connection: QuicConnection, stream: QuicStream?, message: QuicMessage
    ) async
    func didReceiveError(
        connection: QuicConnection, stream: QuicStream, error: QuicError
    ) async
}

actor StreamManager {
    private var uniqueStreams: [StreamKind: QuicStream] = [:]
    private var commonStreams: [QuicStream]

    init() {
        uniqueStreams = [:]
        commonStreams = .init()
    }

    func getUniqueStream(kind: StreamKind) -> QuicStream? {
        uniqueStreams[kind]
    }

    func addUniqueStream(kind: StreamKind, stream: QuicStream) {
        uniqueStreams[kind] = stream
    }

    func removeUniqueStream(kind: StreamKind) {
        _ = uniqueStreams.removeValue(forKey: kind)
    }

    func addCommonStream(_ stream: QuicStream) {
        commonStreams.append(stream)
    }

    func commonContains(_ stream: QuicStream) -> Bool {
        commonStreams.contains { $0 === stream }
    }

    func removeCommonStream(_ stream: QuicStream) {
        commonStreams.removeAll(where: { $0 === stream })
    }

    func changeTypeToCommon(_ stream: QuicStream) {
        removeCommonStream(stream)
        stream.kind = .commonEphemeral
        addCommonStream(stream)
    }

    func closeAllCommonStreams() {
        for stream in commonStreams {
            stream.close()
        }
        commonStreams.removeAll()
    }

    func closeAllUniqueStreams() {
        for stream in uniqueStreams.values {
            stream.close()
        }
        uniqueStreams.removeAll()
    }
}

public class QuicConnection: @unchecked Sendable {
    private var connection: HQuic?
    private let api: UnsafePointer<QuicApiTable>
    private var registration: HQuic?
    private var configuration: HQuic?
    private var streamManager: StreamManager
    private weak var messageHandler: QuicConnectionMessageHandler?
    private var connectionCallback: ConnectionCallback?

    // Initializer for creating a new connection
    init(
        api: UnsafePointer<QuicApiTable>,
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
        api: UnsafePointer<QuicApiTable>, registration: HQuic?, configuration: HQuic?,
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

    // Sets the callback handler for the connection
    func setCallbackHandler() -> QuicStatus {
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
        let status = api.pointee.ConnectionOpen(
            registration,
            { connection, context, event -> QuicStatus in
                return QuicConnection.connectionCallback(
                    connection: connection, context: context, event: event
                )
            }, Unmanaged.passUnretained(self).toOpaque(), &connection
        )
        if status.isFailed {
            throw QuicError.invalidStatus(status: status.code)
        }
    }

    // Creates or retrieves a unique persistent stream
    func createOrGetUniquePersistentStream(kind: StreamKind) async throws -> QuicStream {
        if let stream = await streamManager.getUniqueStream(kind: kind) {
            return stream
        }
        let stream = try QuicStream(api: api, connection: connection, kind, messageHandler: self)
        await streamManager.addUniqueStream(kind: kind, stream: stream)
        return stream
    }

    // Creates a common ephemeral stream
    func createCommonEphemeralStream() async throws -> QuicStream {
        let stream: QuicStream = try QuicStream(
            api: api, connection: connection, .commonEphemeral, messageHandler: self
        )
        await streamManager.addCommonStream(stream)
        return stream
    }

    // Removes a stream from the connection
    func removeStream(stream: QuicStream) async {
        stream.close()
        let cointain = await streamManager.commonContains(stream)
        if cointain {
            await streamManager.removeCommonStream(stream)
        } else {
            await streamManager.removeUniqueStream(kind: stream.kind)
        }
    }

    // Closes the connection and cleans up resources
    func close() async {
        connectionCallback = nil
        messageHandler = nil
        await streamManager.closeAllCommonStreams()
        await streamManager.closeAllUniqueStreams()
        if let connection {
            api.pointee.ConnectionClose(connection)
            self.connection = nil
        }
        logger.debug("QuicConnection Close")
    }

    // Starts the connection with the specified IP address and port
    func start(ipAddress: String, port: UInt16) throws {
        let status = api.pointee.ConnectionStart(
            connection, configuration, QUIC_ADDRESS_FAMILY(QUIC_ADDRESS_FAMILY_UNSPEC),
            ipAddress, port
        )
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
            logger.debug("[\(String(describing: connection))] Connected")

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
                    Task {
                        await messageHandler.didReceiveMessage(
                            connection: quicConnection,
                            stream: nil,
                            message: QuicMessage(type: .shutdownComplete, data: nil)
                        )
                        quicConnection.messageHandler = nil
                    }
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
                await quicConnection.streamManager.addCommonStream(quicStream)
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
        case .changeStreamType:
            Task {
                if stream.kind == .uniquePersistent {
                    await streamManager.changeTypeToCommon(stream)
                }
            }
        default:
            break
        }
        // Call messageHandler safely in the actor context
        Task { [weak self] in
            guard let self else { return }
            await messageHandler?.didReceiveMessage(
                connection: self, stream: stream, message: message
            )
        }
    }

    // Handles errors received from the stream
    public func didReceiveError(_: QuicStream, error: QuicError) {
        logger.error("Failed to receive message: \(error)")
        //       await  messageHandler?.didReceiveError(connection: self, stream: stream, error: error)
    }
}
