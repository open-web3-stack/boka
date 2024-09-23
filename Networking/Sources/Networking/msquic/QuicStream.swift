import Atomics
import Foundation
import Logging
import msquic

let streamLogger = Logger(label: "QuicStream")

public enum StreamKind {
    case uniquePersistent
    case commonEphemeral
    case unknown
}

public protocol QuicStreamMessageHandler: AnyObject {
    func didReceiveMessage(_ stream: QuicStream, message: QuicMessage)
    func didReceiveError(_ stream: QuicStream, error: QuicError)
}

public class QuicStream {
    private var stream: HQuic?
    private let api: UnsafePointer<QuicApiTable>?
    private let connection: HQuic?
    public let kind: StreamKind
    private weak var messageHandler: QuicStreamMessageHandler?
    private var streamCallback: StreamCallback?
    private var sendCompletion: CheckedContinuation<QuicMessage, Error>?
    private let isClosed: ManagedAtomic<Bool> = .init(false)

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
    }

    init(
        api: UnsafePointer<QuicApiTable>?, connection: HQuic?, stream: HQuic?,
        messageHandler: QuicStreamMessageHandler? = nil
    ) {
        self.api = api
        self.connection = connection
        self.messageHandler = messageHandler
        self.stream = stream
        kind = .commonEphemeral
        streamCallback = { stream, context, event in
            QuicStream.streamCallback(
                stream: stream, context: context, event: event
            )
        }
    }

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
        streamLogger.info("[\(String(describing: stream))] Stream opened")
    }

    func start() throws {
        try openStream(kind)
        let status = (api?.pointee.StreamStart(stream, QUIC_STREAM_START_FLAG_NONE)).status
        if status.isFailed {
            throw QuicError.invalidStatus(status: status.code)
        }
        streamLogger.info("[\(String(describing: stream))] Stream started")
    }

    func close() {
        if isClosed.compareExchange(expected: false, desired: true, ordering: .acquiring).exchanged {
            streamLogger.info("QuicStream close")
            streamCallback = nil
            messageHandler = nil
            if stream != nil {
                api?.pointee.StreamClose(stream)
                stream = nil
            }
        }
    }

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

    func send(buffer: Data, kind: StreamKind? = nil) -> QuicStatus {
        streamLogger.info("[\(String(describing: stream))] Sending data...")
        var status = QuicStatusCode.success.rawValue
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

        // Use the provided kind if available, otherwise use the stream's kind
        let effectiveKind = kind ?? self.kind
        let flags = (effectiveKind == .uniquePersistent) ? QUIC_SEND_FLAG_NONE : QUIC_SEND_FLAG_FIN

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

    func send(buffer: Data, kind: StreamKind? = nil) async throws -> QuicMessage {
        streamLogger.info("[\(String(describing: stream))] Sending data...")
        var status = QuicStatusCode.success.rawValue
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

        // Use the provided kind if available, otherwise use the stream's kind
        let effectiveKind = kind ?? self.kind
        let flags = (effectiveKind == .uniquePersistent) ? QUIC_SEND_FLAG_NONE : QUIC_SEND_FLAG_FIN

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

    deinit {
        close()
        streamLogger.info("QuicStream Deinit")
    }
}

extension QuicStream {
    private static func streamCallback(
        stream: HQuic?, context: UnsafeMutableRawPointer?, event: UnsafePointer<QUIC_STREAM_EVENT>?
    ) -> QuicStatus {
        guard let context, let event else {
            return QuicStatusCode.notSupported.rawValue
        }

        let quicStream: QuicStream = Unmanaged<QuicStream>.fromOpaque(context).takeUnretainedValue()
        var status: QuicStatus = QuicStatusCode.success.rawValue
        streamLogger.info("[\(String(describing: stream))] Event: \(event.pointee.Type.rawValue)")
        switch event.pointee.Type {
        case QUIC_STREAM_EVENT_SEND_COMPLETE:
            if let clientContext = event.pointee.SEND_COMPLETE.ClientContext {
                free(clientContext)
            }
            streamLogger.info("[\(String(describing: stream))] Data sent")

        case QUIC_STREAM_EVENT_RECEIVE:
            let bufferCount: UInt32 = event.pointee.RECEIVE.BufferCount
            let buffers = event.pointee.RECEIVE.Buffers
            var receivedData = Data()
            for i in 0 ..< bufferCount {
                let buffer = buffers![Int(i)]
                let bufferLength = Int(buffer.Length)
                let bufferData = Data(bytes: buffer.Buffer, count: bufferLength)
                streamLogger.info(
                    " Data length \(bufferLength) bytes: \(String([UInt8](bufferData).map { Character(UnicodeScalar($0)) }))"
                )
                receivedData.append(bufferData)
            }
            if receivedData.count > 0 {
                if let continuation = quicStream.sendCompletion {
                    continuation.resume(returning: QuicMessage(type: .received, data: receivedData))
                    quicStream.sendCompletion = nil
                }
                quicStream.messageHandler?.didReceiveMessage(
                    quicStream, message: QuicMessage(type: .received, data: receivedData)
                )
            }

        case QUIC_STREAM_EVENT_PEER_SEND_SHUTDOWN:
            streamLogger.info("[\(String(describing: stream))] Peer shut down")
            let message = QuicMessage(type: .shutdown, data: nil)
            quicStream.messageHandler?.didReceiveMessage(quicStream, message: message)

        case QUIC_STREAM_EVENT_PEER_SEND_ABORTED:
            streamLogger.warning("[\(String(describing: stream))] Peer aborted")
            status =
                (quicStream.api?.pointee.StreamShutdown(stream, QUIC_STREAM_SHUTDOWN_FLAG_ABORT, 0))
                    .status
            quicStream.messageHandler?.didReceiveError(
                quicStream, error: QuicError.invalidStatus(status: status.code)
            )

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
