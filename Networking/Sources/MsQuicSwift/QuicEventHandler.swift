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
    func shutdownComplete(_ connection: QuicConnection)
    func streamStarted(_ connect: QuicConnection, stream: QuicStream)

    // stream events
    // nil data indicate end of data stream
    func dataReceived(_ stream: QuicStream, data: Data?)
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
    public func shutdownComplete(_: QuicConnection) {}

    public func streamStarted(_: QuicConnection, stream _: QuicStream) {}

    public func dataReceived(_: QuicStream, data _: Data?) {}

    public func closed(_: QuicStream, status _: QuicStatus, code _: QuicErrorCode) {}
}
