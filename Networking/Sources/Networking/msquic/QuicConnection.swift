import Foundation
import Logging
import msquic

let logger = Logger(label: "QuicConnection")

public class QuicConnection {
    private var connection: HQuic?
    private let api: UnsafePointer<QuicApiTable>?
    private var registration: HQuic?
    private var configuration: HQuic?
    private var streams: AtomicArray<QuicStream> = .init()

    public var onMessageReceived: ((Result<QuicMessage, QuicError>) -> Void)?

    init(api: UnsafePointer<QuicApiTable>?, registration: HQuic?, configuration: HQuic?) {
        self.api = api
        self.registration = registration
        self.configuration = configuration
    }

    init(
        api: UnsafePointer<QuicApiTable>?, registration: HQuic?, configuration: HQuic?,
        connection: HQuic?
    ) {
        self.api = api
        self.registration = registration
        self.configuration = configuration
        self.connection = connection
    }

    // TODO: set callback handler
    func setCallbackHandler() -> QuicStatus {
        guard let api, let connection, let configuration else {
            return QuicStatusCode.invalidParameter.rawValue
        }

        let callbackPointer = unsafeBitCast(
            QuicConnection.connectionCallback, to: UnsafeMutableRawPointer?.self
        )

        api.pointee.SetCallbackHandler(
            connection,
            callbackPointer,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        return api.pointee.ConnectionSetConfiguration(connection, configuration)
    }

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
            quicConnection.onMessageReceived?(.success(QuicMessage(type: .connected, data: nil)))

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
            logger.info("[\(String(describing: connection))] All done")
            if event.pointee.SHUTDOWN_COMPLETE.AppCloseInProgress == 0 {
                // TODO: close all streams
                quicConnection.api?.pointee.ConnectionClose(connection)
                quicConnection.onMessageReceived?(.success(QuicMessage(type: .shutdown, data: nil)))
            }

        case QUIC_CONNECTION_EVENT_RESUMPTION_TICKET_RECEIVED:
            logger.info(
                " Ticket received (\(event.pointee.RESUMPTION_TICKET_RECEIVED.ResumptionTicketLength) bytes)"
            )

        case QUIC_CONNECTION_EVENT_PEER_STREAM_STARTED:
            // TODO: Manage streams
            logger.info("[\(String(describing: connection))] Peer stream started")
            let stream = event.pointee.PEER_STREAM_STARTED.Stream
            let streamHandler = QuicStream(api: quicConnection.api, connection: connection, stream: stream)
            streamHandler.onMessageReceived = quicConnection.onMessageReceived
            streamHandler.setCallbackHandler()

        default:
            break
        }

        return status
    }

    func open() throws {
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

    func getUniquePersistentStream() throws -> QuicStream? {
        streams.first(where: { $0.kind == .uniquePersistent })
    }

    func createStream(_ streamKind: StreamKind = .commonEphemeral) throws -> QuicStream {
        let stream = try QuicStream(api: api, connection: connection, streamKind)
        streams.append(stream)
        return stream
    }

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

    deinit {
        logger.info("QuicConnection Deinit")
    }
}
