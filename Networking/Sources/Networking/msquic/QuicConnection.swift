import Foundation
import msquic

class QuicConnection {
    private var connection: HQuic?
    private let api: UnsafePointer<QuicApiTable>?
    private var registration: HQuic?
    private var configuration: HQuic?
    private var stream: HQuic?
    // private var sendBuffer:QuicBuffer?
    init(api: UnsafePointer<QuicApiTable>?, registration: HQuic?, configuration: HQuic?) throws {
        self.api = api
        self.registration = registration
        self.configuration = configuration
    }

    private static let connectionCallback: ConnectionCallback = { connection, context, event in
        guard let context, let event else {
            return QuicStatusCode.notSupported.rawValue
        }

        let quicConnection: QuicConnection = Unmanaged<QuicConnection>.fromOpaque(context)
            .takeUnretainedValue()
        var status: QuicStatus = QuicStatusCode.success.rawValue
        switch event.pointee.Type {
        case QUIC_CONNECTION_EVENT_CONNECTED:
            // The handshake has completed for the connection.
            print("[conn][\(String(describing: connection))] Connected")
            // ClientSend(connection)
            quicConnection.clientSend(message: Data("hello world".utf8))

        case QUIC_CONNECTION_EVENT_SHUTDOWN_INITIATED_BY_TRANSPORT:
            // The connection has been shut down by the transport.
            if event.pointee.SHUTDOWN_INITIATED_BY_TRANSPORT.Status
                == QuicStatusCode.connectionIdle.rawValue
            {
                print("[conn][\(String(describing: connection))] Successfully shut down on idle.")
            } else {
                print(
                    "[conn][\(String(describing: connection))] Shut down by transport, 0x\(String(format: "%x", event.pointee.SHUTDOWN_INITIATED_BY_TRANSPORT.Status))"
                )
            }

        case QUIC_CONNECTION_EVENT_SHUTDOWN_INITIATED_BY_PEER:
            // The connection was explicitly shut down by the peer.
            print(
                "[conn][\(String(describing: connection))] Shut down by peer, 0x\(String(format: "%llx", event.pointee.SHUTDOWN_INITIATED_BY_PEER.ErrorCode))"
            )

        case QUIC_CONNECTION_EVENT_SHUTDOWN_COMPLETE:
            // The connection has completed the shutdown process and is ready to be safely cleaned up.
            print("[conn][\(String(describing: connection))] All done")
            if event.pointee.SHUTDOWN_COMPLETE.AppCloseInProgress == 0 {
                quicConnection.api?.pointee.ConnectionClose(connection)
            }

        case QUIC_CONNECTION_EVENT_RESUMPTION_TICKET_RECEIVED:
            // A resumption ticket was received from the server.
            print(
                "[conn][\(String(describing: connection))] Resumption ticket received (\(event.pointee.RESUMPTION_TICKET_RECEIVED.ResumptionTicketLength) bytes)"
            )

        default:
            break
        }

        return status
    }

    private static let streamCallback: StreamCallback = { stream, context, event in
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
            print("[strm][\(String(describing: stream))] Data sent")

        case QUIC_STREAM_EVENT_RECEIVE:
            let bufferCount = event.pointee.RECEIVE.BufferCount
            let buffers = event.pointee.RECEIVE.Buffers
            for i in 0 ..< bufferCount {
                let buffer = buffers![Int(i)]
                let bufferLength = Int(buffer.Length)
                let bufferData = Data(bytes: buffer.Buffer, count: bufferLength)
                print("[strm] Data received: \(String(describing: bufferData))")
            }

        case QUIC_STREAM_EVENT_PEER_SEND_SHUTDOWN:
            print("[strm][\(String(describing: stream))] Peer shut down")

        case QUIC_STREAM_EVENT_PEER_SEND_ABORTED:
            print("[strm][\(String(describing: stream))] Peer aborted")
            status =
                (quicConnection.api?.pointee.StreamShutdown(
                    stream, QUIC_STREAM_SHUTDOWN_FLAG_ABORT, 0
                ))
                .status

        case QUIC_STREAM_EVENT_SHUTDOWN_COMPLETE:
            print("[strm][\(String(describing: stream))] All done")
            if event.pointee.SHUTDOWN_COMPLETE.AppCloseInProgress == 0 {
                quicConnection.api?.pointee.StreamClose(stream)
            }

        default:
            break
        }

        return status
    }

    func open() throws {
        // let status =
        //     (api?.pointee.ConnectionOpen(
        //         registration,
        //         { _, context, event -> QuicStatus in

        //             let quicConnection = Unmanaged<QuicConnection>.fromOpaque(context!)
        //                 .takeUnretainedValue()
        //             return quicConnection.handleEvent(event)
        //         }, Unmanaged.passUnretained(self).toOpaque(), &connection
        //     )).status

        let status =
            (api?.pointee.ConnectionOpen(
                registration,
                { connection, context, event -> QuicStatus in
                    return QuicConnection.connectionCallback(connection, context, event)
                }, Unmanaged.passUnretained(self).toOpaque(), &connection
            )).status
        if status.isFailed {
            throw QuicError.invalidStatus(status: status.code)
        }
    }

//    private func handleEvent(_ event: UnsafePointer<QUIC_CONNECTION_EVENT>?) -> QuicStatus {
//        // guard let event else {
//        // return QuicStatusCode.connectionIdle.rawValue
//        // }
//
//        var status: QuicStatus = QuicStatusCode.success.rawValue
//        switch event?.pointee.Type {
//        case QUIC_CONNECTION_EVENT_CONNECTED:
//            print("Connected")
//            clientSend(message: Data("sample".utf8))
//
//        case QUIC_CONNECTION_EVENT_SHUTDOWN_COMPLETE:
//            print("Connection shutdown complete")
//            if event?.pointee.SHUTDOWN_COMPLETE.AppCloseInProgress == 0 {
//                relese()
//            }
//
//        default:
//            break
//        }
//        return status
//    }

    func clientSend(message: Data) {
        // Create/allocate a new bidirectional stream.
        var status =
            (api?.pointee.StreamOpen(
                connection, QUIC_STREAM_OPEN_FLAG_NONE, QuicConnection.streamCallback, Unmanaged.passUnretained(self).toOpaque(), &stream
            )).status
        if status.isFailed {
            print("StreamOpen failed, \(status)!")

            api?.pointee.StreamClose(stream)
        }

        print("[strm][\(String(describing: stream))] Starting...")

        // Starts the bidirectional stream.
        status = (api?.pointee.StreamStart(stream, QUIC_STREAM_START_FLAG_NONE)).status
        if status.isFailed {
            print("StreamStart failed, \(status)!")
            api?.pointee.StreamClose(stream)
        }

        print("[strm][\(String(describing: stream))] Sending data...")
        let buffer = message
        let bufferPointer = UnsafeMutablePointer<UInt8>.allocate(
            capacity: buffer.count
        )
        buffer.copyBytes(to: bufferPointer, count: buffer.count)
        var sendBuffer = QuicBuffer(Length: UInt32(buffer.count), Buffer: bufferPointer)
        // Sends the buffer over the stream. Note the FIN flag is passed along with
        // the buffer. This indicates this is the last buffer on the stream and the
        // the stream is shut down (in the send direction) immediately after.
        status =
            (api?.pointee.StreamSend(stream, &sendBuffer, 1, QUIC_SEND_FLAG_FIN, nil))
                .status
        if status.isFailed {
            print("StreamSend failed, \(status)!")

            let shutdown =
                (api?.pointee.StreamShutdown(stream, QUIC_STREAM_SHUTDOWN_FLAG_ABORT, 0))
                    .status
            if shutdown.isFailed {
                print("StreamShutdown failed, 0x\(String(format: "%x", shutdown))!")
            }
        }
    }

    func start(ipAddress: String, port: UInt16) throws {
        let status =
            (api?.pointee.ConnectionStart(
                connection, configuration, UInt8(QUIC_ADDRESS_FAMILY_UNSPEC), ipAddress, port
            )).status
        if status.isFailed {
            throw QuicError.invalidStatus(status: status.code)
        }
    }

//    func relese() {
//        if connection != nil {
//            print("Connection Close")
//            api?.pointee.ConnectionClose(connection)
//            connection = nil
//        }
//    }

    deinit {
        print("QuicConnection Deinit")

//        relese()
    }
}
