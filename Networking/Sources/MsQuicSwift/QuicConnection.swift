import Foundation
import Logging
import msquic
import Utils

private struct Storage {
    let handle: ConnectionHandle
    let registration: QuicRegistration
    let configuration: QuicConfiguration
    var state: State
}

private enum State {
    case opened
    case started
    // Storage nil means closed
}

public final class QuicConnection: Sendable {
    public let id: UniqueId
    private let logger: Logger
    private let storage: ThreadSafeContainer<Storage?>
    fileprivate let handler: QuicEventHandler

    var ptr: OpaquePointer? {
        storage.read { $0?.handle.ptr }
    }

    var api: QuicAPI? {
        storage.read { $0?.registration.api }
    }

    // create new connection from local
    public init(
        handler: QuicEventHandler,
        registration: QuicRegistration,
        configuration: QuicConfiguration
    ) throws(QuicError) {
        id = "QuicConnection".uniqueId
        logger = Logger(label: id)
        self.handler = handler

        let registrationPtr = registration.ptr
        var ptr: HQUIC?
        let callback: QUIC_CONNECTION_CALLBACK_HANDLER = connectionCallback
        try registration.api.call("ConnectionOpen") { api in
            api.pointee.ConnectionOpen(
                registrationPtr,
                callback,
                nil,
                &ptr
            )
        }

        let handle = ConnectionHandle(logger: logger, ptr: ptr!, api: registration.api)

        storage = .init(.init(
            handle: handle,
            registration: registration,
            configuration: configuration,
            state: .opened
        ))

        handle.connection = self
    }

    // wrapping a remote connection initiated by peer
    init(
        handler: QuicEventHandler,
        registration: QuicRegistration,
        configuration: QuicConfiguration,
        connection: HQUIC
    ) throws(QuicError) {
        id = "QuicConnection".uniqueId
        logger = Logger(label: id)
        self.handler = handler

        let handle = ConnectionHandle(logger: logger, ptr: connection, api: registration.api)

        storage = .init(.init(
            handle: handle,
            registration: registration,
            configuration: configuration,
            state: .started
        ))

        handle.connection = self

        try registration.api.call("ConnectionSetConfiguration") { api in
            api.pointee.ConnectionSetConfiguration(connection, configuration.ptr)
        }
    }

    deinit {
        storage.read { storage in
            if let storage {
                storage.registration.api.call { api in
                    api.pointee.ConnectionClose(storage.handle.ptr)
                }
            }
        }
    }

    public func connect(to address: NetAddr) throws {
        logger.debug("connecting to \(address)")
        try storage.write { storage in
            guard var storage2 = storage else {
                throw QuicError.alreadyClosed
            }
            guard storage2.state == .opened else {
                throw QuicError.alreadyStarted
            }
            let (host, port) = address.getAddressAndPort()
            try storage2.registration.api.call("ConnectionStart") { api in
                api.pointee.ConnectionStart(
                    storage2.handle.ptr,
                    storage2.configuration.ptr,
                    QUIC_ADDRESS_FAMILY(QUIC_ADDRESS_FAMILY_UNSPEC),
                    host, port
                )
            }
            storage2.state = .started
            storage = storage2
        }
    }

    fileprivate func close() {
        storage.write { storage in
            storage = nil
        }
    }

    public func shutdown(errorCode: QuicErrorCode = .success) throws {
        logger.debug("closing connection")
        try storage.write { storage in
            guard let storage2 = storage else {
                throw QuicError.alreadyClosed
            }
            guard storage2.state == .started else {
                throw QuicError.notStarted
            }
            storage2.registration.api.call { api in
                api.pointee.ConnectionShutdown(
                    storage2.handle.ptr,
                    QUIC_CONNECTION_SHUTDOWN_FLAG_NONE,
                    errorCode.code
                )
            }
            self.handler.shutdownInitiated(self, reason: .byLocal(code: errorCode))
            storage = nil
        }
    }

    public func createStream() throws -> QuicStream {
        logger.debug("creating stream")

        return try storage.read { storage in
            guard let storage, storage.state == .started else {
                throw QuicError.notStarted
            }

            return try QuicStream(connection: self, handler: handler)
        }
    }

    public func getRemoteAddress() throws -> NetAddr {
        var addr = QUIC_ADDR()
        var size = UInt32(MemoryLayout<QUIC_ADDR>.size)
        let res: ()? = try? api?.call("GetParam") { api in
            api.pointee.GetParam(
                ptr,
                UInt32(QUIC_PARAM_CONN_REMOTE_ADDRESS),
                &size,
                &addr
            )
        }
        if res == nil {
            throw QuicError.unableToGetRemoteAddress
        }
        return NetAddr(quicAddr: addr)
    }
}

// Not sendable. msquic ensures callbacks for a connection are always delivered serially
// https://github.com/microsoft/msquic/blob/main/docs/API.md#execution-mode
// This is retained by the msquic connection as it has to outlive the connection
private class ConnectionHandle {
    let logger: Logger
    let ptr: OpaquePointer
    let api: QuicAPI
    weak var connection: QuicConnection?

    init(logger: Logger, ptr: OpaquePointer, api: QuicAPI) {
        self.logger = logger
        self.ptr = ptr
        self.api = api

        let handler: QUIC_CONNECTION_CALLBACK_HANDLER = connectionCallback
        let handlerPtr = unsafeBitCast(handler, to: UnsafeMutableRawPointer?.self)

        api.call { api in
            api.pointee.SetCallbackHandler(
                ptr,
                handlerPtr,
                Unmanaged.passRetained(self).toOpaque() // !! retain +1
            )
        }
    }

    fileprivate func callbackHandler(event: UnsafePointer<QUIC_CONNECTION_EVENT>) -> QuicStatus {
        switch event.pointee.Type {
        case QUIC_CONNECTION_EVENT_PEER_CERTIFICATE_RECEIVED:
            logger.debug("Peer certificate received")
            if let connection {
                let evtData = event.pointee.PEER_CERTIFICATE_RECEIVED
                let data: Data?
                if let certPtr = evtData.Certificate {
                    let cert = certPtr.assumingMemoryBound(to: QUIC_BUFFER.self)
                    data = Data(bytes: cert.pointee.Buffer, count: Int(cert.pointee.Length))
                } else {
                    data = nil
                }

                return connection.handler.shouldOpen(connection, certificate: data)
            }

        case QUIC_CONNECTION_EVENT_CONNECTED:
            logger.trace("Connected")
            if let connection {
                connection.handler.connected(connection)
            }

        case QUIC_CONNECTION_EVENT_SHUTDOWN_INITIATED_BY_TRANSPORT:
            let evtData = event.pointee.SHUTDOWN_INITIATED_BY_TRANSPORT
            let status = QuicStatus(rawValue: evtData.Status)
            if status == .code(.connectionIdle) {
                logger.trace("Successfully shut down on idle.")
                if let connection {
                    connection.handler.shutdownInitiated(connection, reason: .idle)
                }
            } else {
                logger.debug("Shut down by transport. Status: \(status) Error: \(evtData.ErrorCode)")
                if let connection {
                    connection.handler.shutdownInitiated(
                        connection,
                        reason: .transport(status: QuicStatus(rawValue: evtData.Status), code: QuicErrorCode(evtData.ErrorCode))
                    )
                }
            }

        case QUIC_CONNECTION_EVENT_SHUTDOWN_INITIATED_BY_PEER:
            logger.debug("Shut down by peer. Error: \(event.pointee.SHUTDOWN_INITIATED_BY_PEER.ErrorCode)")
            if let connection {
                let errorCode = QuicErrorCode(event.pointee.SHUTDOWN_INITIATED_BY_PEER.ErrorCode)
                connection.handler.shutdownInitiated(connection, reason: .byPeer(code: errorCode))
            }

        case QUIC_CONNECTION_EVENT_SHUTDOWN_COMPLETE:
            logger.debug("Shutdown complete")
            if let connection {
                connection.handler.shutdownComplete(connection)
            }
            if event.pointee.SHUTDOWN_COMPLETE.AppCloseInProgress == 0 {
                // avoid closing twice
                connection?.close()
                api.call { api in
                    api.pointee.ConnectionClose(ptr)
                }
            }
            Unmanaged.passUnretained(self).release() // !! release -1

        case QUIC_CONNECTION_EVENT_PEER_STREAM_STARTED:
            logger.debug("Peer stream started")
            let streamPtr = event.pointee.PEER_STREAM_STARTED.Stream
            if let connection {
                let stream = QuicStream(connection: connection, stream: streamPtr!, handler: connection.handler)
                connection.handler.streamStarted(connection, stream: stream)
            } else {
                logger.warning("Stream started but connection is gone?")
                api.call { api in
                    api.pointee.StreamClose(streamPtr)
                }
            }

        default:
            break
        }

        return .code(.success)
    }
}

private func connectionCallback(
    connection _: OpaquePointer?,
    context: UnsafeMutableRawPointer?,
    event: UnsafeMutablePointer<QUIC_CONNECTION_EVENT>?
) -> UInt32 {
    let handle = Unmanaged<ConnectionHandle>.fromOpaque(context!)
        .takeUnretainedValue()

    return handle.callbackHandler(event: event!).rawValue
}
