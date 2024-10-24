import Foundation
import MsQuicSwift
import Utils

public final class MockPeerEventHandler: QuicEventHandler {
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

    public func shouldOpen(_: QuicConnection, certificate: Data?) -> QuicStatus {
        guard let certificate else {
            return .code(.requiredCert)
        }
        do {
            let (publicKey, alternativeName) = try parseCertificate(data: certificate, type: .x509)
            if alternativeName != generateSubjectAlternativeName(pubkey: publicKey) {
                return .code(.badCert)
            }
        } catch {
            return .code(.badCert)
        }
        return .code(.success)
    }

    public func connected(_ connection: QuicConnection) {
        events.write { events in
            events.append(.connected(connection: connection))
        }
    }

    public func shutdownInitiated(_ connection: QuicConnection, reason: ConnectionCloseReason) {
        print("shutdownInitiated \(connection.id) with reason \(reason)")
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
        print("closed stream \(stream.id) with status \(status) and code \(code)")
        events.write { events in
            events.append(.closed(stream: stream, status: status, code: code))
        }
    }
}
