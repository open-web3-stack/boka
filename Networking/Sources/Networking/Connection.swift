import Foundation
import MsQuicSwift
import TracingUtils
import Utils

private let logger = Logger(label: "Connection")

public final class Connection<Handler: StreamHandler>: Sendable {
    let connection: QuicConnection
    let impl: PeerImpl<Handler>
    let mode: PeerMode
    let remoteAddress: NetAddr
    let presistentStreams: ThreadSafeContainer<
        [Handler.PresistentHandler.StreamKind: Stream<Handler>]
    > = .init([:])
    let initiatedByLocal: Bool

    public var id: UniqueId {
        connection.id
    }

    init(_ connection: QuicConnection, impl: PeerImpl<Handler>, mode: PeerMode, remoteAddress: NetAddr, initiatedByLocal: Bool) {
        self.connection = connection
        self.impl = impl
        self.mode = mode
        self.remoteAddress = remoteAddress
        self.initiatedByLocal = initiatedByLocal
    }

    @discardableResult
    func createPreistentStream(kind: Handler.PresistentHandler.StreamKind) throws -> Stream<Handler>? {
        let stream = presistentStreams.read { presistentStreams in
            presistentStreams[kind]
        }
        if let stream {
            return stream
        }
        let newStream = try presistentStreams.write { presistentStreams in
            if let stream = presistentStreams[kind] {
                return stream
            }
            let stream = try self.createStream(kind: kind.rawValue)
            presistentStreams[kind] = stream
            return stream
        }
        runPresistentStreamLoop(initiatedByLocal: true, stream: newStream, kind: kind)
        return newStream
    }

    func runPresistentStreamLoop(
        initiatedByLocal: Bool,
        stream: Stream<Handler>,
        kind: Handler.PresistentHandler.StreamKind
    ) {
        presistentStreamRunLoop(
            initiatedByLocal: initiatedByLocal,
            kind: kind,
            logger: logger,
            handler: impl.presistentStreamHandler,
            connection: self,
            stream: stream
        )
    }

    func createStream(kind: UInt8) throws -> Stream<Handler> {
        let stream = try Stream(connection.createStream(), impl: impl)
        impl.addStream(stream)
        try stream.send(data: Data([kind]))
        return stream
    }

    func createStream(kind: Handler.EphemeralHandler.StreamKind) throws -> Stream<Handler> {
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
            if let upKind = Handler.PresistentHandler.StreamKind(rawValue: byte) {
                // TODO: handle duplicated UP streams
                presistentStreams.write { presistentStreams in
                    presistentStreams[upKind] = stream
                }
                runPresistentStreamLoop(initiatedByLocal: false, stream: stream, kind: upKind)
                return
            }
            if let ceKind = Handler.EphemeralHandler.StreamKind(rawValue: byte) {
                logger.debug("stream opened. kind: \(ceKind)")
                // TODO: handle requests
            }
        }
    }
}

func presistentStreamRunLoop<Handler: StreamHandler>(
    initiatedByLocal: Bool,
    kind: Handler.PresistentHandler.StreamKind,
    logger: Logger,
    handler: Handler.PresistentHandler,
    connection: Connection<Handler>,
    stream: Stream<Handler>
) {
    Task.detached {
        do {
            if initiatedByLocal {
                try stream.send(data: Data([kind.rawValue]))
            }
            try handler.streamOpened(stream: stream, kind: kind)
        } catch {
            logger.debug(
                "Failed to setup presistent stream",
                metadata: ["connectionId": "\(connection.id)", "streamId": "\(stream.id)", "kind": "\(kind)", "error": "\(error)"]
            )
        }
        logger.debug(
            "Starting presistent stream run loop",
            metadata: ["connectionId": "\(connection.id)", "streamId": "\(stream.id)", "kind": "\(kind)"]
        )
        do {
            while let data = await stream.receive() {
                try handler.dataReceived(stream: stream, kind: kind, data: data)
            }
            logger.debug(
                "Ending presistent stream run loop",
                metadata: ["connectionId": "\(connection.id)", "streamId": "\(stream.id)", "kind": "\(kind)"]
            )
        } catch {
            logger.debug(
                "Failed to handle presistent stream data",
                metadata: ["connectionId": "\(connection.id)", "streamId": "\(stream.id)", "kind": "\(kind)", "error": "\(error)"]
            )
            stream.close(abort: true)
        }
    }
}
