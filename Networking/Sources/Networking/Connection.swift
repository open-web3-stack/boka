import Foundation
import MsQuicSwift
import TracingUtils
import Utils

private let logger = Logger(label: "Connection")

public final class Connection: Sendable {
    let connection: QuicConnection
    let impl: PeerImpl
    let mode: PeerMode
    let remoteAddress: NetAddr
    let presistentStreams: ThreadSafeContainer<[UniquePresistentStreamKind: Stream]> = .init([:])

    init(_ connection: QuicConnection, impl: PeerImpl, mode: PeerMode, remoteAddress: NetAddr) {
        self.connection = connection
        self.impl = impl
        self.mode = mode
        self.remoteAddress = remoteAddress
    }

    public func getStream(kind: UniquePresistentStreamKind) throws -> Stream {
        let stream = presistentStreams.read { presistentStreams in
            presistentStreams[kind]
        }
        return try stream ?? presistentStreams.write { presistentStreams in
            if let stream = presistentStreams[kind] {
                return stream
            }
            let stream = try self.createStream(kind: kind.rawValue)
            presistentStreams[kind] = stream
            return stream
        }
    }

    private func createStream(kind: UInt8) throws -> Stream {
        let stream = try Stream(connection.createStream(), impl: impl)
        impl.addStream(stream)
        try stream.send(data: Data([kind]))
        return stream
    }

    public func createStream(kind: CommonEphemeralStreamKind) throws -> Stream {
        try createStream(kind: kind.rawValue)
    }

    func streamStarted(stream: QuicStream) {
        let stream = Stream(stream, impl: impl)
        impl.addStream(stream)
        Task {
            guard let byte = await stream.receiveByte() else {
                logger.debug("stream closed without receiving kind. status: \(stream.status)")
                return
            }
            if let upKind = UniquePresistentStreamKind(rawValue: byte) {
                // TODO: handle duplicated UP streams
                presistentStreams.write { presistentStreams in
                    presistentStreams[upKind] = stream
                }
                return
            }
            if let ceKind = CommonEphemeralStreamKind(rawValue: byte) {
                logger.debug("stream opened. kind: \(ceKind)")
                // TODO: handle requests
            }
        }
    }
}
