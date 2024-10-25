import AsyncChannels
import Foundation
import MsQuicSwift
import TracingUtils
import Utils

private let logger = Logger(label: "Connection")

public protocol ConnectionInfoProtocol {
    var id: UniqueId { get }
    var role: PeerRole { get }
    var remoteAddress: NetAddr { get }
}

enum ConnectionError: Error {
    case receiveFailed
    case invalidLength
}

public final class Connection<Handler: StreamHandler>: Sendable, ConnectionInfoProtocol {
    let connection: QuicConnection
    let impl: PeerImpl<Handler>
    public let role: PeerRole
    public let remoteAddress: NetAddr
    let presistentStreams: ThreadSafeContainer<
        [Handler.PresistentHandler.StreamKind: Stream<Handler>]
    > = .init([:])
    let initiatedByLocal: Bool

    public var id: UniqueId {
        connection.id
    }

    init(_ connection: QuicConnection, impl: PeerImpl<Handler>, role: PeerRole, remoteAddress: NetAddr, initiatedByLocal: Bool) {
        self.connection = connection
        self.impl = impl
        self.role = role
        self.remoteAddress = remoteAddress
        self.initiatedByLocal = initiatedByLocal
    }

    public func close(abort: Bool = false) {
        try? connection.shutdown(errorCode: abort ? 1 : 0) // TODO: define some error code
    }

    public func decodeLength(from data: Data) throws -> UInt32 {
        guard data.count >= 4 else {
            throw ConnectionError.invalidLength
        }
        return UInt32(littleEndian: data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
    }

    public func request(_ request: Handler.EphemeralHandler.Request) async throws -> Data {
        let data = try request.encode()
        let kind = request.kind
        let stream = try createStream(kind: kind)
        try stream.send(message: data)

        var reps = Data()
        while let nextData = await stream.receive() {
            if nextData.isEmpty { // fin flag
                break
            }
            let length = try decodeLength(from: nextData.prefix(4))
            let data = nextData.dropFirst(4).prefix(Int(length))
            reps.append(data)
        }

        return reps
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
                presistentStreams.write { presistentStreams in
                    presistentStreams[upKind] = stream
                }
                runPresistentStreamLoop(stream: stream, kind: upKind)
                return
            }
            if let ceKind = Handler.EphemeralHandler.StreamKind(rawValue: byte) {
                logger.debug("stream opened. kind: \(ceKind)")

                var decoder = impl.ephemeralStreamHandler.createDecoder(kind: ceKind)

                let lengthData = await stream.receive(count: 4)
                guard let lengthData, let length = try? decodeLength(from: lengthData) else {
                    stream.close(abort: true)
                    logger.debug("Invalid request length")
                    return
                }
                guard length < 1024 * 1024 * 10 else {
                    stream.close(abort: true)
                    logger.debug("Invalid request length: \(length)")
                    return
                }
                let data = await stream.receive(count: Int(length))
                guard let data else {
                    stream.close(abort: true)
                    logger.debug("Invalid request data")
                    return
                }
                let request = try decoder.decode(data: data)
                let resp = try await impl.ephemeralStreamHandler.handle(connection: self, request: request)
                try stream.send(message: resp, finish: true)
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
        var decoder = handler.createDecoder(kind: kind)
        do {
            while true {
                let lengthData = await stream.receive(count: 4)
                guard let lengthData, let length = try? connection.decodeLength(from: lengthData) else {
                    break
                }
                guard length < 1024 * 1024 * 10 else {
                    stream.close(abort: true)
                    logger.debug("Invalid message length: \(length)")
                    return
                }
                let data = await stream.receive(count: Int(length))
                guard let data else {
                    break
                }
                let msg = try decoder.decode(data: data)
                try await handler.handle(connection: connection, message: msg)
            }
        } catch {
            logger.debug("UP stream run loop failed: \(error)")
            stream.close(abort: true)
        }

        logger.debug(
            "Ending presistent stream run loop",
            metadata: ["connectionId": "\(connection.id)", "streamId": "\(stream.id)", "kind": "\(kind)"]
        )
    }
}
