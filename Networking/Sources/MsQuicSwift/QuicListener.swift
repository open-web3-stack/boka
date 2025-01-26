import Foundation
import Logging
import msquic
import Utils

public final class QuicListener: Sendable {
    public let id: UniqueId
    private let logger: Logger

    fileprivate let handler: QuicEventHandler
    fileprivate let registration: QuicRegistration
    fileprivate let configuration: QuicConfiguration
    private let ptr: SendableOpaquePointer

    public init(
        handler: QuicEventHandler,
        registration: QuicRegistration,
        configuration: QuicConfiguration,
        listenAddress: NetAddr,
        alpns: [Data]
    ) throws {
        id = "QuicListener".uniqueId
        logger = Logger(label: id)
        self.handler = handler
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

        var address = listenAddress.quicAddr

        try alpns.withContentUnsafeBytes { alpnPtrs in
            var buffer = [QUIC_BUFFER](repeating: QUIC_BUFFER(), count: alpnPtrs.count)
            for (i, alpnPtr) in alpnPtrs.enumerated() {
                buffer[i].Length = UInt32(alpnPtr.count)
                buffer[i].Buffer = UnsafeMutablePointer(
                    mutating: alpnPtr.bindMemory(to: UInt8.self).baseAddress!
                )
            }

            try registration.api.call("ListenerStart") { api in
                api.pointee.ListenerStart(ptr, &buffer, UInt32(alpnPtrs.count), &address)
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

            let evtData = event.pointee.NEW_CONNECTION
            let ptr = evtData.Connection
            guard let listener = listener.value else {
                logger.warning("New connection but listener is going")
                return .code(.aborted)
            }

            let connection = try? QuicConnection(
                handler: listener.handler,
                registration: listener.registration,
                configuration: listener.configuration,
                connection: ptr!
            )

            guard let connection else {
                logger.warning("New connection but failed to create")
                return .code(.aborted)
            }

            let evtInfo = evtData.Info!
            let info = ConnectionInfo(
                localAddress: NetAddr(quicAddr: evtInfo.pointee.LocalAddress.pointee),
                remoteAddress: NetAddr(quicAddr: evtInfo.pointee.RemoteAddress.pointee),
                negotiatedAlpn: Data(bytes: evtInfo.pointee.NegotiatedAlpn, count: Int(evtInfo.pointee.NegotiatedAlpnLength)),
                serverName: evtInfo.pointee.ServerNameLength == 0 ? "" : String(
                    bytes: Data(bytes: evtInfo.pointee.ServerName, count: Int(evtInfo.pointee.ServerNameLength)),
                    encoding: .utf8
                ) ?? ""
            )

            return listener.handler.newConnection(listener, connection: connection, info: info)

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
