import Foundation
import Logging
import msquic

let logger = Logger(label: "QuicConnection")

class QuicConnection {
    var connection: HQuic?
    private let api: UnsafePointer<QuicApiTable>?
    private var registration: HQuic?
    private var configuration: HQuic?
    private var streams: AtomicArray<QuicStream> = .init()

    public var onMessageReceived: ((Result<QuicMessage, QuicError>) -> Void)?

    init(api: UnsafePointer<QuicApiTable>?, registration: HQuic?, configuration: HQuic?) throws {
        self.api = api
        self.registration = registration
        self.configuration = configuration
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
            logger.info("[conn][\(String(describing: connection))] Connected")
            quicConnection.onMessageReceived?(.success(QuicMessage(type: .connected, data: nil)))

        case QUIC_CONNECTION_EVENT_SHUTDOWN_INITIATED_BY_TRANSPORT:
            if event.pointee.SHUTDOWN_INITIATED_BY_TRANSPORT.Status
                == QuicStatusCode.connectionIdle.rawValue
            {
                logger.info("[conn][\(String(describing: connection))] Successfully shut down on idle.")
            } else {
                logger.warning(
                    "[conn] Shut down by transport, 0x\(String(format: "%x", event.pointee.SHUTDOWN_INITIATED_BY_TRANSPORT.Status))"
                )
            }

        case QUIC_CONNECTION_EVENT_SHUTDOWN_INITIATED_BY_PEER:
            logger.warning(
                "[conn] Shut down by peer, 0x\(String(format: "%llx", event.pointee.SHUTDOWN_INITIATED_BY_PEER.ErrorCode))"
            )

        case QUIC_CONNECTION_EVENT_SHUTDOWN_COMPLETE:
            logger.info("[conn][\(String(describing: connection))] All done")
            if event.pointee.SHUTDOWN_COMPLETE.AppCloseInProgress == 0 {
                // TODO: close all streams
                quicConnection.api?.pointee.ConnectionClose(connection)
                quicConnection.onMessageReceived?(.success(QuicMessage(type: .shutdown, data: nil)))
            }

        case QUIC_CONNECTION_EVENT_RESUMPTION_TICKET_RECEIVED:
            logger.info(
                "[conn] Ticket received (\(event.pointee.RESUMPTION_TICKET_RECEIVED.ResumptionTicketLength) bytes)"
            )

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

    func createStream() throws -> QuicStream {
        let stream = try QuicStream(api: api, connection: connection)
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
