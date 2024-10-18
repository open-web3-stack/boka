import AsyncChannels
import Foundation
import MsQuicSwift
import TracingUtils
import Utils

private let logger = Logger(label: "Connection")

public protocol ConnectionInfoProtocol {
    var id: UniqueId { get }
    var mode: PeerMode { get }
    var remoteAddress: NetAddr { get }
}

public final class Connection<Handler: StreamHandler>: Sendable, ConnectionInfoProtocol {
    let connection: QuicConnection
    let impl: PeerImpl<Handler>
    public let mode: PeerMode
    public let remoteAddress: NetAddr
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

    public func close(abort: Bool = false) {
        try? connection.shutdown(errorCode: abort ? 1 : 0) // TODO: define some error code
    }

    public func request(_ request: Handler.EphemeralHandler.Request) async throws -> Data {
        let data = try request.encode()
        let kind = request.kind
        let stream = try createStream(kind: kind)
        try stream.send(data: data)
        // TODO: pipe this to decoder directly to be able to reject early
        var response = Data()
        while let nextData = await stream.receive() {
            response.append(nextData)
        }
        return response
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
            let stream = try self.createStream(kind: kind)
            presistentStreams[kind] = stream
            return stream
        }
        runPresistentStreamLoop(stream: newStream, kind: kind)
        return newStream
    }

    func runPresistentStreamLoop(
        stream: Stream<Handler>,
        kind: Handler.PresistentHandler.StreamKind
    ) {
        presistentStreamRunLoop(
            kind: kind,
            logger: logger,
            handler: impl.presistentStreamHandler,
            connection: self,
            stream: stream
        )
    }

    func createStream(kind: UInt8, presistentKind: Handler.PresistentHandler.StreamKind?) throws -> Stream<Handler> {
        let stream = try Stream(connection.createStream(), connectionId: id, impl: impl, kind: presistentKind)
        impl.addStream(stream)
        try stream.send(data: Data([kind]))
        return stream
    }

    func createStream(kind: Handler.PresistentHandler.StreamKind) throws -> Stream<Handler> {
        try createStream(kind: kind.rawValue, presistentKind: kind)
    }

    func createStream(kind: Handler.EphemeralHandler.StreamKind) throws -> Stream<Handler> {
        try createStream(kind: kind.rawValue, presistentKind: nil)
    }

    func streamStarted(stream: QuicStream) {
        let stream = Stream(stream, connectionId: id, impl: impl)
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
                runPresistentStreamLoop(stream: stream, kind: upKind)
                return
            }
            if let ceKind = Handler.EphemeralHandler.StreamKind(rawValue: byte) {
                logger.debug("stream opened. kind: \(ceKind)")

                let complete = Channel<Void>()
                var decoder = impl.ephemeralStreamHandler.createDecoder(kind: ceKind) { result in
                    switch result {
                    case let .success(request):
                        Task {
                            await complete.receive()
                            do {
                                let resp = try await self.impl.ephemeralStreamHandler.handle(connection: self, request: request)
                                try stream.send(data: resp, finish: true)
                            } catch {
                                logger.debug("Failed to handle request: \(error)")
                                stream.close(abort: true)
                            }
                        }
                    case let .failure(error):
                        logger.debug("Failed to decode request: \(error)")
                        stream.close(abort: true)
                    }
                }
                do {
                    while let data = await stream.receive() {
                        try decoder.decode(data: data)
                    }
                    decoder.finish()
                } catch {
                    logger.debug("Failed to decode request: \(error)")
                    stream.close(abort: true)
                }
                await complete.send(())
            }
        }
    }

    func streamClosed(stream: Stream<Handler>, abort: Bool) {
        stream.closed(abort: abort)
        if let kind = stream.kind {
            presistentStreams.write { presistentStreams in
                presistentStreams[kind] = nil
            }
        }
    }
}

func presistentStreamRunLoop<Handler: StreamHandler>(
    kind: Handler.PresistentHandler.StreamKind,
    logger: Logger,
    handler: Handler.PresistentHandler,
    connection: Connection<Handler>,
    stream: Stream<Handler>
) {
    Task.detached {
        do {
            try await handler.streamOpened(connection: connection, stream: stream, kind: kind)
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
        var decoder = handler.createDecoder(kind: kind) { result in
            switch result {
            case let .success(message):
                Task {
                    do {
                        try await handler.handle(connection: connection, message: message)
                    } catch {
                        logger.debug(
                            "Failed to handle presistent stream data",
                            metadata: [
                                "connectionId": "\(connection.id)",
                                "streamId": "\(stream.id)",
                                "kind": "\(kind)",
                                "error": "\(error)",
                            ]
                        )
                        stream.close(abort: true)
                    }
                }
            case let .failure(error):
                logger.debug("Failed to decode message: \(error)")
            }
        }
        while let data = await stream.receive() {
            try decoder.decode(data: data)
        }

        decoder.finish()
        logger.debug(
            "Ending presistent stream run loop",
            metadata: ["connectionId": "\(connection.id)", "streamId": "\(stream.id)", "kind": "\(kind)"]
        )
    }
}
