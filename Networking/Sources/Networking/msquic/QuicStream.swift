import Foundation
import Logging
import msquic

let streamLogger = Logger(label: "QuicStream")

public enum StreamKind: Sendable {
    case uniquePersistent
    case commonEphemeral
    case unknown
}

public protocol QuicStreamMessageHandler: AnyObject {
    func didReceiveMessage(_ stream: QuicStream, message: QuicMessage)
    func didReceiveError(_ stream: QuicStream, error: QuicError)
}

public class QuicStream: @unchecked Sendable {
    private var stream: HQuic?
    private let api: UnsafePointer<QuicApiTable>?
    private let connection: HQuic?
    public var kind: StreamKind
    private weak var messageHandler: QuicStreamMessageHandler?
    private var streamCallback: StreamCallback?
    private var sendCompletion: CheckedContinuation<QuicMessage, Error>?
    // Initializer for creating a new stream
    init(
        api: UnsafePointer<QuicApiTable>?, connection: HQuic?,
        _ streamKind: StreamKind = .uniquePersistent,
        messageHandler: QuicStreamMessageHandler? = nil
    ) throws {
        self.api = api
        self.connection = connection
        self.messageHandler = messageHandler
        kind = streamKind
        streamCallback = { stream, context, event in
            QuicStream.streamCallback(
                stream: stream, context: context, event: event
            )
        }
        try start()
    }

    // Initializer for wrapping an existing stream
    init(
        api: UnsafePointer<QuicApiTable>?, connection: HQuic?, stream: HQuic?,
        _ streamKind: StreamKind = .uniquePersistent,
        messageHandler: QuicStreamMessageHandler? = nil
    ) {
        self.api = api
        self.connection = connection
        self.messageHandler = messageHandler
        self.stream = stream
        kind = streamKind
        streamCallback = { stream, context, event in
            QuicStream.streamCallback(
                stream: stream, context: context, event: event
            )
        }
    }

    // Deinitializer to ensure resources are cleaned up
    deinit {
        streamLogger.info("QuicStream Deinit")
    }

    // Opens a stream with the specified kind
    private func openStream(_: StreamKind = .commonEphemeral) throws {
        let status =
            (api?.pointee.StreamOpen(
                connection, QUIC_STREAM_OPEN_FLAG_NONE,
                { stream, context, event -> QuicStatus in
                    QuicStream.streamCallback(stream: stream, context: context, event: event)
                }, Unmanaged.passUnretained(self).toOpaque(), &stream
            )).status
        if status.isFailed {
            throw QuicError.invalidStatus(status: status.code)
        }
    }

    // Starts the stream
    private func start() throws {
        try openStream(kind)
        let status = (api?.pointee.StreamStart(stream, QUIC_STREAM_START_FLAG_NONE)).status
        if status.isFailed {
            throw QuicError.invalidStatus(status: status.code)
        }
        streamLogger.info("[\(String(describing: stream))] Stream started")
    }

    // Closes the stream and cleans up resources
    func close() {
        streamCallback = nil
        messageHandler = nil
        if let stream {
            api?.pointee.StreamClose(stream)
            self.stream = nil
        }
        streamLogger.info("QuicStream close")
    }

    // Sets the callback handler for the stream
    func setCallbackHandler() {
        guard let api, let stream else {
            return
        }

        let callbackPointer = unsafeBitCast(
            streamCallback, to: UnsafeMutableRawPointer?.self
        )

        api.pointee.SetCallbackHandler(
            stream,
            callbackPointer,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
    }

    func respond(with data: Data, kind: StreamKind? = nil) -> QuicStatus {
        streamLogger.info("[\(String(describing: stream))] Respond data...")
        var status = QuicStatusCode.success.rawValue
        let messageLength = data.count

        let sendBufferRaw = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<QuicBuffer>.size + messageLength,
            alignment: MemoryLayout<QuicBuffer>.alignment
        )

        let sendBuffer = sendBufferRaw.assumingMemoryBound(to: QuicBuffer.self)
        let bufferPointer = UnsafeMutablePointer<UInt8>.allocate(
            capacity: messageLength
        )
        data.copyBytes(to: bufferPointer, count: messageLength)

        sendBuffer.pointee.Buffer = bufferPointer
        sendBuffer.pointee.Length = UInt32(messageLength)

        // Use the provided kind if available, otherwise use the stream's kind
        let effectiveKind = kind ?? self.kind
        let flags = (effectiveKind == .uniquePersistent) ? QUIC_SEND_FLAG_NONE : QUIC_SEND_FLAG_FIN
        streamLogger
            .info(
                "[\(String(describing: stream))] flags \((effectiveKind == .uniquePersistent) ? "QUIC_SEND_FLAG_NONE" : "QUIC_SEND_FLAG_FIN")"
            )
        status = (api?.pointee.StreamSend(stream, sendBuffer, 1, flags, sendBufferRaw)).status
        if status.isFailed {
            streamLogger.error("StreamSend failed, \(status)!")
            let shutdown: QuicStatus =
                (api?.pointee.StreamShutdown(stream, QUIC_STREAM_SHUTDOWN_FLAG_ABORT, 0)).status
            if shutdown.isFailed {
                streamLogger.error("StreamShutdown failed, 0x\(String(format: "%x", shutdown))!")
            }
        }
        return status
    }

    // Sends data over the stream asynchronously and waits for the response
    func send(data: Data, kind: StreamKind? = nil) async throws -> QuicMessage {
        streamLogger.info("[\(String(describing: stream))] Sending data...")
        var status = QuicStatusCode.success.rawValue
        let messageLength = data.count

        let sendBufferRaw = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<QuicBuffer>.size + messageLength,
            alignment: MemoryLayout<QuicBuffer>.alignment
        )

        let sendBuffer = sendBufferRaw.assumingMemoryBound(to: QuicBuffer.self)
        let bufferPointer = UnsafeMutablePointer<UInt8>.allocate(
            capacity: messageLength
        )
        data.copyBytes(to: bufferPointer, count: messageLength)

        sendBuffer.pointee.Buffer = bufferPointer
        sendBuffer.pointee.Length = UInt32(messageLength)

        // Use the provided kind if available, otherwise use the stream's kind
        let effectiveKind = kind ?? self.kind
        let flags = (effectiveKind == .uniquePersistent) ? QUIC_SEND_FLAG_NONE : QUIC_SEND_FLAG_FIN
        streamLogger
            .info(
                "[\(String(describing: stream))] flags \((effectiveKind == .uniquePersistent) ? "QUIC_SEND_FLAG_NONE" : "QUIC_SEND_FLAG_FIN")"
            )

        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self else {
                continuation.resume(throwing: QuicError.sendFailed)
                return
            }
            sendCompletion = continuation
            status = (api?.pointee.StreamSend(stream, sendBuffer, 1, flags, sendBufferRaw)).status
            if status.isFailed {
                streamLogger.error("StreamSend failed, \(status)!")
                let shutdown: QuicStatus =
                    (api?.pointee.StreamShutdown(stream, QUIC_STREAM_SHUTDOWN_FLAG_ABORT, 0)).status
                if shutdown.isFailed {
                    streamLogger.error(
                        "StreamShutdown failed, 0x\(String(format: "%x", shutdown))!"
                    )
                }
                continuation.resume(throwing: QuicError.invalidStatus(status: status.code))
                sendCompletion = nil
            }
        }
    }
}

extension QuicStream {
    // Static callback function for handling stream events
    private static func streamCallback(
        stream: HQuic?, context: UnsafeMutableRawPointer?, event: UnsafePointer<QUIC_STREAM_EVENT>?
    ) -> QuicStatus {
        guard let context, let event else {
            return QuicStatusCode.notSupported.rawValue
        }

        let quicStream: QuicStream = Unmanaged<QuicStream>.fromOpaque(context).takeUnretainedValue()
        var status: QuicStatus = QuicStatusCode.success.rawValue
        switch event.pointee.Type {
        case QUIC_STREAM_EVENT_SEND_COMPLETE:
            if let clientContext = event.pointee.SEND_COMPLETE.ClientContext {
                free(clientContext)
            }
            streamLogger.info("[\(String(describing: stream))] Stream send completed")

        case QUIC_STREAM_EVENT_RECEIVE:

            let bufferCount: UInt32 = event.pointee.RECEIVE.BufferCount
            let buffers = event.pointee.RECEIVE.Buffers
            var receivedData = Data()
            for i in 0 ..< bufferCount {
                let buffer = buffers![Int(i)]
                let bufferLength = Int(buffer.Length)
                let bufferData = Data(bytes: buffer.Buffer, count: bufferLength)
                receivedData.append(bufferData)
            }

            if receivedData.count > 0 {
                if event.pointee.RECEIVE.Flags.rawValue & QUIC_RECEIVE_FLAG_FIN.rawValue != 0 {
                    streamLogger.warning("[\(String(describing: stream))] FIN received in QUIC stream")
                    quicStream.messageHandler?.didReceiveMessage(quicStream, message: QuicMessage(type: .changeStreamType, data: nil))
                    quicStream.kind = .commonEphemeral
                }
                if let continuation = quicStream.sendCompletion {
                    continuation.resume(returning: QuicMessage(type: .received, data: receivedData))
                    quicStream.sendCompletion = nil
                }
                quicStream.messageHandler?.didReceiveMessage(
                    quicStream, message: QuicMessage(type: .received, data: receivedData)
                )
            }

        case QUIC_STREAM_EVENT_PEER_SEND_SHUTDOWN:
            streamLogger.warning("[\(String(describing: stream))] Peer send shutdown")
            if quicStream.kind == .uniquePersistent {
                status =
                    (quicStream.api?.pointee.StreamShutdown(stream, QUIC_STREAM_SHUTDOWN_FLAG_GRACEFUL, 0))
                        .status
            }

        case QUIC_STREAM_EVENT_PEER_SEND_ABORTED:
            streamLogger.error("[\(String(describing: stream))] Peer send aborted")
            status =
                (quicStream.api?.pointee.StreamShutdown(stream, QUIC_STREAM_SHUTDOWN_FLAG_ABORT, 0))
                    .status

        case QUIC_STREAM_EVENT_SHUTDOWN_COMPLETE:
            streamLogger.info("[\(String(describing: stream))] All done")
            if event.pointee.SHUTDOWN_COMPLETE.AppCloseInProgress == 0 {
                quicStream.api?.pointee.StreamClose(stream)
            }
            if let continuation = quicStream.sendCompletion {
                continuation.resume(throwing: QuicError.sendFailed)
                quicStream.sendCompletion = nil
            }

        default:
            break
        }

        return status
    }
}
