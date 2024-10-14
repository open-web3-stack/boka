import Foundation
import Logging
import msquic
import Utils

private let logger = Logger(label: "QuicStream")

private struct Storage {
    let handle: StreamHandle
    let connection: QuicConnection
}

public final class QuicStream: Sendable {
    private let logger: Logger
    private let storage: ThreadSafeContainer<Storage?>
    fileprivate let eventBus: EventBus

    public var events: some Subscribable {
        eventBus
    }

    // create new stream from local
    init(
        connection: QuicConnection,
        eventBus: EventBus
    ) throws(QuicError) {
        logger = Logger(label: "QuicStream".uniqueId)
        self.eventBus = eventBus

        let api = connection.api!

        var ptr: HQUIC?
        let handler: QUIC_STREAM_CALLBACK_HANDLER = streamCallback
        try api.call("StreamOpen") { api in
            api.pointee.StreamOpen(
                connection.ptr, QUIC_STREAM_OPEN_FLAG_NONE,
                handler,
                nil,
                &ptr
            )
        }

        let handle = StreamHandle(logger: logger, ptr: ptr!, api: api)

        try api.call("StreamStart") { api in
            api.pointee.StreamStart(ptr, QUIC_STREAM_START_FLAG_NONE)
        }

        storage = .init(.init(
            handle: handle,
            connection: connection
        ))

        handle.stream = self
    }

    // wrapping a remote stream initiated by peer
    init(
        connection: QuicConnection,
        stream: HQUIC,
        eventBus: EventBus
    ) {
        logger = Logger(label: "QuicStream".uniqueId)
        self.eventBus = eventBus

        let handle = StreamHandle(logger: logger, ptr: stream, api: connection.api!)

        storage = .init(.init(
            handle: handle,
            connection: connection
        ))

        handle.stream = self
    }

    public func shutdown(errorCode: QuicErrorCode = .success) throws {
        logger.debug("closing stream")

        try storage.mutate { storage in
            guard let storage2 = storage else {
                throw QuicError.alreadyClosed
            }
            try storage2.connection.api?.call("StreamShutdown") { api in
                api.pointee.StreamShutdown(
                    storage2.handle.ptr,
                    errorCode == .success ? QUIC_STREAM_SHUTDOWN_FLAG_GRACEFUL : QUIC_STREAM_SHUTDOWN_FLAG_ABORT,
                    errorCode.code
                )
            }

            storage = nil
        }
    }

    public func send(with data: Data, startStream: Bool = false, closeStream: Bool = false) throws {
        logger.trace("Sending \(data.count) bytes")

        try storage.read { storage in
            guard let storage, let api = storage.connection.api else {
                throw QuicError.alreadyClosed
            }

            let messageLength = data.count

            let sendBufferRaw = UnsafeMutableRawPointer.allocate( // !! allocate
                byteCount: MemoryLayout<QUIC_BUFFER>.size + messageLength,
                alignment: MemoryLayout<QUIC_BUFFER>.alignment
            )

            let sendBuffer = sendBufferRaw.assumingMemoryBound(to: QUIC_BUFFER.self)
            let bufferPointer = sendBufferRaw.advanced(by: MemoryLayout<QUIC_BUFFER>.size).assumingMemoryBound(to: UInt8.self)
            data.copyBytes(to: bufferPointer, count: messageLength) // TODO: figure out a better way to avoid memory copy here

            sendBuffer.pointee.Buffer = bufferPointer
            sendBuffer.pointee.Length = UInt32(messageLength)

            var sendFlag = QUIC_SEND_FLAG_NONE.rawValue
            if startStream {
                sendFlag |= QUIC_SEND_FLAG_START.rawValue
            }
            if closeStream {
                sendFlag |= QUIC_SEND_FLAG_FIN.rawValue
            }

            let result = Result {
                try api.call("StreamSend") { api in
                    api.pointee.StreamSend(storage.handle.ptr, sendBuffer, 1, QUIC_SEND_FLAGS(sendFlag), sendBufferRaw)
                }
            }

            switch result {
            case .success:
                break
            case let .failure(error):
                sendBufferRaw.deallocate() // !! deallocate
                throw error
            }
        }
    }
}

// Not sendable. msquic ensures callbacks for a connection are always delivered serially
// https://github.com/microsoft/msquic/blob/main/docs/API.md#execution-mode
// This is retained by the msquic stream as it has to outlive the stream
private class StreamHandle {
    let logger: Logger
    let ptr: OpaquePointer
    let api: QuicAPI
    weak var stream: QuicStream?

    init(logger: Logger, ptr: OpaquePointer, api: QuicAPI) {
        self.logger = logger
        self.ptr = ptr
        self.api = api

        let handler: QUIC_STREAM_CALLBACK_HANDLER = streamCallback
        let handlerPtr = unsafeBitCast(handler, to: UnsafeMutableRawPointer?.self)

        api.call { api in
            api.pointee.SetCallbackHandler(
                ptr,
                handlerPtr,
                Unmanaged.passRetained(self).toOpaque() // !! retain +1
            )
        }
    }

    fileprivate func callbackHandler(event: UnsafePointer<QUIC_STREAM_EVENT>) -> QuicStatus {
        switch event.pointee.Type {
        case QUIC_STREAM_EVENT_SEND_COMPLETE:
            logger.trace("Stream send completed")
            if let clientContext = event.pointee.SEND_COMPLETE.ClientContext {
                clientContext.deallocate() // !! deallocate
            }

        case QUIC_STREAM_EVENT_RECEIVE:
            let bufferCount: UInt32 = event.pointee.RECEIVE.BufferCount
            let buffers = event.pointee.RECEIVE.Buffers
            var totalSize = 0

            for i in 0 ..< Int(bufferCount) {
                let buffer = buffers![i]
                totalSize += Int(buffer.Length)
            }

            logger.trace("Stream received \(totalSize) bytes")

            var receivedData = Data(capacity: totalSize)

            for i in 0 ..< Int(bufferCount) {
                let buffer = buffers![i]
                let bufferLength = Int(buffer.Length)
                receivedData.append(buffer.Buffer, count: bufferLength)
            }

            if totalSize > 0 {
                if let stream {
                    stream.eventBus.publish(QuicEvents.StreamReceived(stream: stream, data: receivedData))
                } else {
                    logger.warning("Stream received data but it is already gone?")
                }
            }

        case QUIC_STREAM_EVENT_PEER_SEND_SHUTDOWN:
            logger.trace("Peer send shutdown")

        case QUIC_STREAM_EVENT_PEER_SEND_ABORTED:
            logger.trace("Peer send aborted")

        case QUIC_STREAM_EVENT_SHUTDOWN_COMPLETE:
            logger.trace("Stream shutdown complete")

            let evtData = event.pointee.SHUTDOWN_COMPLETE
            if let stream {
                stream.eventBus.publish(
                    QuicEvents.StreamClosed(
                        stream: stream,
                        errorCode: .init(evtData.ConnectionErrorCode),
                        closeStatus: .init(rawValue: evtData.ConnectionCloseStatus)
                    )
                )
            }

            if event.pointee.SHUTDOWN_COMPLETE.AppCloseInProgress == 0 {
                api.call { api in
                    api.pointee.StreamClose(ptr)
                }
            }

            Unmanaged.passUnretained(self).release() // !! release -1

        default:
            break
        }

        return .code(.success)
    }
}

private func streamCallback(
    stream _: OpaquePointer?,
    context: UnsafeMutableRawPointer?,
    event: UnsafeMutablePointer<QUIC_STREAM_EVENT>?
) -> UInt32 {
    let handle = Unmanaged<StreamHandle>.fromOpaque(context!)
        .takeUnretainedValue()

    return handle.callbackHandler(event: event!).rawValue
}
