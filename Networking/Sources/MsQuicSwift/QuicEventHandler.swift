import Foundation
import Utils

public enum ConnectionCloseReason: Equatable, Sendable {
    case idle
    case transport(status: QuicStatus, code: QuicErrorCode)
    case byPeer(code: QuicErrorCode)
    case byLocal(code: QuicErrorCode)
}

public struct ConnectionInfo: Sendable {
    public let localAddress: NetAddr
    public let remoteAddress: NetAddr
    public let negotiatedAlpn: Data
    public let serverName: String

    public init(
        localAddress: NetAddr, remoteAddress: NetAddr, negotiatedAlpn: Data, serverName: String
    ) {
        self.localAddress = localAddress
        self.remoteAddress = remoteAddress
        self.negotiatedAlpn = negotiatedAlpn
        self.serverName = serverName
    }
}

public protocol QuicEventHandler: Sendable {
    // listener events
    func newConnection(_ listener: QuicListener, connection: QuicConnection, info: ConnectionInfo)
        -> QuicStatus

    // connection events
    func shouldOpen(_ connection: QuicConnection, certificate: Data?) -> QuicStatus
    func connected(_ connection: QuicConnection)
    func shutdownInitiated(_ connection: QuicConnection, reason: ConnectionCloseReason)
    func streamStarted(_ connect: QuicConnection, stream: QuicStream)

    // stream events
    func dataReceived(_ stream: QuicStream, data: Data)
    func closed(_ stream: QuicStream, status: QuicStatus, code: QuicErrorCode)
}

// default implementations
extension QuicEventHandler {
    public func newConnection(_: QuicListener, connection _: QuicConnection, info _: ConnectionInfo)
        -> QuicStatus
    {
        .code(.success)
    }

    public func shouldOpen(_: QuicConnection, certificate _: Data?) -> QuicStatus {
        .code(.success)
    }

    public func connected(_: QuicConnection) {}

    public func shutdownInitiated(_: QuicConnection, reason _: ConnectionCloseReason) {}

    public func streamStarted(_: QuicConnection, stream _: QuicStream) {}

    public func dataReceived(_: QuicStream, data _: Data) {}

    public func closed(_: QuicStream, status _: QuicStatus, code _: QuicErrorCode) {}
}

public final class MockQuicEventHandler: QuicEventHandler {
    public enum EventType {
        case newConnection(listener: QuicListener, connection: QuicConnection, info: ConnectionInfo)
        case shouldOpen(connection: QuicConnection, certificate: Data?)
        case connected(connection: QuicConnection)
        case shutdownInitiated(connection: QuicConnection, reason: ConnectionCloseReason)
        case streamStarted(connection: QuicConnection, stream: QuicStream)
        case dataReceived(stream: QuicStream, data: Data)
        case closed(stream: QuicStream, status: QuicStatus, code: QuicErrorCode)
    }

    public let events: ThreadSafeContainer<[EventType]> = .init([])

    public init() {}

    public func newConnection(
        _ listener: QuicListener, connection: QuicConnection, info: ConnectionInfo
    ) -> QuicStatus {
        events.write { events in
            events.append(.newConnection(listener: listener, connection: connection, info: info))
        }

        return .code(.success)
    }

    public func shouldOpen(_ connection: QuicConnection, certificate: Data?) -> QuicStatus {
        events.write { events in
            events.append(.shouldOpen(connection: connection, certificate: certificate))
        }

        return .code(.success)
    }

    public func connected(_ connection: QuicConnection) {
        events.write { events in
            events.append(.connected(connection: connection))
        }
    }

    public func shutdownInitiated(_ connection: QuicConnection, reason: ConnectionCloseReason) {
        events.write { events in
            events.append(.shutdownInitiated(connection: connection, reason: reason))
        }
    }

    public func streamStarted(_ connect: QuicConnection, stream: QuicStream) {
        events.write { events in
            events.append(.streamStarted(connection: connect, stream: stream))
        }
    }

    public func dataReceived(_ stream: QuicStream, data: Data) {
        events.write { events in
            events.append(.dataReceived(stream: stream, data: data))
        }
    }

    public func closed(_ stream: QuicStream, status: QuicStatus, code: QuicErrorCode) {
        events.write { events in
            events.append(.closed(stream: stream, status: status, code: code))
        }
    }
}
