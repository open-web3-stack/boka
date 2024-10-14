import Foundation
import Utils

public enum QuicEvents {
    public struct ConnectionConnected: Event {
        public let connection: QuicConnection
        public let remoteAddress: NetAddr

        public init(connection: QuicConnection, remoteAddress: NetAddr) {
            self.connection = connection
            self.remoteAddress = remoteAddress
        }
    }

    public struct ConnectionShutdown: Event {
        public let connection: QuicConnection

        public init(connection: QuicConnection) {
            self.connection = connection
        }
    }

    public struct StreamStarted: Event {
        public let connection: QuicConnection
        public let stream: QuicStream

        public init(connection: QuicConnection, stream: QuicStream) {
            self.connection = connection
            self.stream = stream
        }
    }

    public struct StreamClosed: Event {
        public let stream: QuicStream
        public let connectionErrorCode: QuicErrorCode
        public let connectionCloseStatus: QuicStatus

        public init(stream: QuicStream, errorCode: QuicErrorCode, closeStatus: QuicStatus) {
            self.stream = stream
            connectionErrorCode = errorCode
            connectionCloseStatus = closeStatus
        }
    }

    public struct StreamReceived: Event {
        public let stream: QuicStream
        public let data: Data

        public init(stream: QuicStream, data: Data) {
            self.stream = stream
            self.data = data
        }
    }

    public struct ConnectionAccepted: Event {
        public let connection: QuicConnection

        public init(connection: QuicConnection) {
            self.connection = connection
        }
    }
}
