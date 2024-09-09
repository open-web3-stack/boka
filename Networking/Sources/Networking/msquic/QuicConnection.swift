import Foundation
import Logging
import msquic

let logger = Logger(label: "QuicConnection")

class QuicConnection {
    private var connection: HQuic?
    private let api: UnsafePointer<QuicApiTable>?
    private var registration: HQuic?
    private var configuration: HQuic?
    private var streams = AtomicArray<HQuic>()

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
                quicConnection.api?.pointee.ConnectionClose(connection)
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

    private static func streamCallback(
        stream: HQuic?, context: UnsafeMutableRawPointer?, event: UnsafePointer<QUIC_STREAM_EVENT>?
    ) -> QuicStatus {
        guard let context, let event else {
            return QuicStatusCode.notSupported.rawValue
        }

        let quicConnection: QuicConnection = Unmanaged<QuicConnection>.fromOpaque(context)
            .takeUnretainedValue()
        var status: QuicStatus = QuicStatusCode.success.rawValue

        switch event.pointee.Type {
        case QUIC_STREAM_EVENT_SEND_COMPLETE:
            if let clientContext = event.pointee.SEND_COMPLETE.ClientContext {
                free(clientContext)
            }
            logger.info("[strm][\(String(describing: stream))] Data sent")

        case QUIC_STREAM_EVENT_RECEIVE:
            let bufferCount: UInt32 = event.pointee.RECEIVE.BufferCount
            let buffers = event.pointee.RECEIVE.Buffers
            for i in 0 ..< bufferCount {
                let buffer = buffers![Int(i)]
                let bufferLength = Int(buffer.Length)
                let bufferData = Data(bytes: buffer.Buffer, count: bufferLength)
                logger.info(
                    "[strm] Data length \(bufferLength) bytes: \(String([UInt8](bufferData).map { Character(UnicodeScalar($0)) }))"
                )
                let message = QuicMessage(type: .received, data: bufferData)
                quicConnection.onMessageReceived?(.success(message))
            }

        case QUIC_STREAM_EVENT_PEER_SEND_SHUTDOWN:
            logger.info("[strm][\(String(describing: stream))] Peer shut down")
            let message = QuicMessage(type: .shutdown, data: nil)
            quicConnection.onMessageReceived?(.success(message))

        case QUIC_STREAM_EVENT_PEER_SEND_ABORTED:
            logger.warning("[strm][\(String(describing: stream))] Peer aborted")
            status =
                (quicConnection.api?.pointee.StreamShutdown(
                    stream, QUIC_STREAM_SHUTDOWN_FLAG_ABORT, 0
                ))
                .status
            quicConnection.onMessageReceived?(.failure(QuicError.invalidStatus(status: status.code)))

        case QUIC_STREAM_EVENT_SHUTDOWN_COMPLETE:
            logger.info("[strm][\(String(describing: stream))] All done")
            if event.pointee.SHUTDOWN_COMPLETE.AppCloseInProgress == 0 {
                quicConnection.api?.pointee.StreamClose(stream)
                quicConnection.streams.removeFirstIfExist { $0 == stream }
            }

        default:
            let message = QuicMessage(type: .unknown, data: nil)
            quicConnection.onMessageReceived?(.success(message))
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

    func clientSend(buffer: Data) {
        var stream: HQuic?
        var status =
            (api?.pointee.StreamOpen(
                connection, QUIC_STREAM_OPEN_FLAG_NONE,
                { stream, context, event -> QuicStatus in
                    QuicConnection.streamCallback(stream: stream, context: context, event: event)
                }, Unmanaged.passUnretained(self).toOpaque(), &stream
            )).status
        if status.isFailed {
            logger.error("StreamOpen failed, \(status)!")
            api?.pointee.StreamClose(stream)
            return
        }

        logger.info("[strm][\(String(describing: stream))] Starting...")

        streams.append(stream!)

        status = (api?.pointee.StreamStart(stream, QUIC_STREAM_START_FLAG_NONE)).status
        if status.isFailed {
            logger.error("StreamStart failed, \(status)!")
            api?.pointee.StreamClose(stream)
            streams.removeFirstIfExist { $0 == stream }
            return
        }

        logger.info("[strm][\(String(describing: stream))] Sending data...")
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
        status =
            (api?.pointee.StreamSend(stream, sendBuffer, 1, QUIC_SEND_FLAG_FIN, sendBufferRaw))
                .status
        if status.isFailed {
            logger.error("StreamSend failed, \(status)!")
            let shutdown =
                (api?.pointee.StreamShutdown(stream, QUIC_STREAM_SHUTDOWN_FLAG_ABORT, 0))
                    .status
            if shutdown.isFailed {
                logger.error("StreamShutdown failed, 0x\(String(format: "%x", shutdown))!")
            }
            streams.removeFirstIfExist { $0 == stream }
        }
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
