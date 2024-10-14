import Foundation
import Logging
import msquic
import Utils

public final class QuicListener: Sendable {
    private let logger: Logger

    fileprivate let eventBus: EventBus
    fileprivate let registration: QuicRegistration
    fileprivate let configuration: QuicConfiguration
    private let ptr: SendableOpaquePointer

    public var events: some Subscribable {
        eventBus
    }

    public init(
        eventBus: EventBus,
        registration: QuicRegistration,
        configuration: QuicConfiguration,
        listenAddress: NetAddr,
        alpn: Data
    ) throws {
        logger = Logger(label: "QuicListener".uniqueId)
        self.eventBus = eventBus
        self.registration = registration
        self.configuration = configuration

        let handler: QUIC_LISTENER_CALLBACK_HANDLER = listenerCallback

        var ptr: HQUIC?
        try registration.api.call("ListenerOpen") { api in
            api.pointee.ListenerOpen(
                registration.ptr,
                handler,
                nil,
                &ptr
            )
        }

        self.ptr = ptr!.asSendable

        _ = ListenerHandle(logger: logger, ptr: ptr!, api: registration.api, listener: self)

        let address = listenAddress.toQuicAddr()
        guard var address else {
            throw QuicError.invalidAddress(listenAddress)
        }

        try alpn.withUnsafeBytes { alpnPtr in
            var buffer = QUIC_BUFFER(
                Length: UInt32(alpnPtr.count),
                Buffer: UnsafeMutablePointer(
                    mutating: alpnPtr.bindMemory(to: UInt8.self).baseAddress!
                )
            )

            try registration.api.call("ListenerStart") { api in
                api.pointee.ListenerStart(ptr, &buffer, 1, &address)
            }
        }
    }

    deinit {
        registration.api.call { api in
            api.pointee.ListenerStop(ptr.value)
        }
    }

    public func listenAddress() throws -> NetAddr {
        var address = QUIC_ADDR()
        var size = UInt32(MemoryLayout<QUIC_ADDR>.size)
        try registration.api.call("GetParam") { api in
            api.pointee.GetParam(
                ptr.value,
                UInt32(QUIC_PARAM_LISTENER_LOCAL_ADDRESS),
                &size,
                &address
            )
        }
        return NetAddr(quicAddr: address)
    }
}

private final class ListenerHandle: Sendable {
    let logger: Logger
    let ptr: SendableOpaquePointer
    let api: QuicAPI
    let listener: WeakRef<QuicListener>

    init(logger: Logger, ptr: OpaquePointer, api: QuicAPI, listener: QuicListener) {
        self.logger = logger
        self.ptr = ptr.asSendable
        self.api = api
        self.listener = .init(listener)

        let handler: QUIC_LISTENER_CALLBACK_HANDLER = listenerCallback
        let handlerPtr = unsafeBitCast(handler, to: UnsafeMutableRawPointer?.self)

        api.call { api in
            api.pointee.SetCallbackHandler(
                ptr,
                handlerPtr,
                Unmanaged.passRetained(self).toOpaque() // !! retain +1
            )
        }
    }

    fileprivate func callbackHandler(event: UnsafePointer<QUIC_LISTENER_EVENT>) -> QuicStatus {
        switch event.pointee.Type {
        case QUIC_LISTENER_EVENT_NEW_CONNECTION:
            logger.debug("New connection")

            // TODO: be able to reject connection
            let ptr = event.pointee.NEW_CONNECTION.Connection
            guard let listener = listener.value else {
                logger.warning("New connection but listener is going")
                return .code(.aborted)
            }

            let connection = try? QuicConnection(
                registration: listener.registration,
                configuration: listener.configuration,
                connection: ptr!,
                eventBus: listener.eventBus
            )

            guard let connection else {
                logger.warning("New connection but failed to create")
                return .code(.aborted)
            }

            listener.eventBus.publish(QuicEvents.ConnectionAccepted(connection: connection))

        case QUIC_LISTENER_EVENT_STOP_COMPLETE:
            logger.debug("Stop complete")

            api.call { api in
                api.pointee.ListenerClose(ptr.value)
            }

            Unmanaged.passUnretained(self).release() // !! release -1

        default:
            break
        }

        return .code(.success)
    }
}

private func listenerCallback(
    connection _: OpaquePointer?,
    context: UnsafeMutableRawPointer?,
    event: UnsafeMutablePointer<QUIC_LISTENER_EVENT>?
) -> UInt32 {
    let handle = Unmanaged<ListenerHandle>.fromOpaque(context!)
        .takeUnretainedValue()

    return handle.callbackHandler(event: event!).rawValue
}
