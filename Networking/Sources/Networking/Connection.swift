import AsyncChannels
import Foundation
import MsQuicSwift
import Synchronization
import TracingUtils
import Utils

private let logger = Logger(label: "Connection")

public protocol ConnectionInfoProtocol {
    var id: UniqueId { get }
    var role: PeerRole { get }
    var remoteAddress: NetAddr { get }
    var publicKey: Data? { get }

    func ready() async throws
}

enum ConnectionError: Error {
    case receiveFailed
    case invalidLength
    case unexpectedState
    case closed
    case reconnect
}

enum ConnectionState {
    case connecting(continuations: [CheckedContinuation<Void, Error>])
    case connected(publicKey: Data)
    case closed
    case closing
    case reconnect(publicKey: Data)
}

public final class Connection<Handler: StreamHandler>: Sendable, ConnectionInfoProtocol {
    let connection: QuicConnection
    let impl: PeerImpl<Handler>

    public let role: PeerRole
    public let remoteAddress: NetAddr
    private let lastActive: Atomic<TimeInterval> = Atomic(0)
    let presistentStreams: ThreadSafeContainer<
        [Handler.PresistentHandler.StreamKind: Stream<Handler>]
    > = .init([:])
    let initiatedByLocal: Bool
    private let state: ThreadSafeContainer<ConnectionState> = .init(.connecting(continuations: []))

    public var publicKey: Data? {
        state.read {
            switch $0 {
            case .connecting:
                nil
            case let .connected(publicKey):
                publicKey
            case .closed, .closing:
                nil
            case let .reconnect(publicKey):
                publicKey
            }
        }
    }

    func getLastActive() -> TimeInterval {
        lastActive.load(ordering: .sequentiallyConsistent)
    }

    public var id: UniqueId {
        connection.id
    }

    init(_ connection: QuicConnection, impl: PeerImpl<Handler>, role: PeerRole, remoteAddress: NetAddr, initiatedByLocal: Bool) {
        self.connection = connection
        self.impl = impl
        self.role = role
        self.remoteAddress = remoteAddress
        self.initiatedByLocal = initiatedByLocal
        updateLastActive()
    }

    func updateLastActive() {
        lastActive.store(Date().timeIntervalSince1970, ordering: .releasing)
    }

    func opened(publicKey: Data) throws {
        try state.write { state in
            if case let .connecting(continuations) = state {
                for continuation in continuations {
                    continuation.resume()
                }
                state = .connected(publicKey: publicKey)
            } else {
                throw ConnectionError.unexpectedState
            }
        }
    }

    func closed() {
        state.write { state in
            if case let .connecting(continuations) = state {
                for continuation in continuations {
                    continuation.resume(throwing: ConnectionError.closed)
                }
            }
            state = .closed
        }
    }

    func closing() {
        state.write { state in
            if case let .connecting(continuations) = state {
                for continuation in continuations {
                    continuation.resume(throwing: ConnectionError.closed)
                }
            }
            state = .closing
        }
    }

    func reconnect(publicKey: Data) {
        state.write { state in
            if case let .connecting(continuations) = state {
                for continuation in continuations {
                    continuation.resume(throwing: ConnectionError.reconnect)
                }
            }
            state = .reconnect(publicKey: publicKey)
        }
    }

    public var isClosed: Bool {
        state.read {
            switch $0 {
            case .closed, .closing:
                true
            case .connected, .reconnect, .connecting:
                false
            }
        }
    }

    public var needReconnect: Bool {
        state.read {
            if case .reconnect = $0 {
                return true
            }
            return false
        }
    }

    public func ready() async throws {
        let isReady = state.read {
            switch $0 {
            case .connecting:
                false
            case .connected, .closed, .closing, .reconnect:
                true
            }
        }

        if isReady {
            return
        }
        try await withCheckedThrowingContinuation { continuation in
            state.write { state in
                if case var .connecting(continuations) = state {
                    continuations.append(continuation)
                    state = .connecting(continuations: continuations)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    public func close(abort: Bool = false) {
        closing()
        try? connection.shutdown(errorCode: abort ? 1 : 0) // TODO: define some error code
    }

    public func request(_ request: Handler.EphemeralHandler.Request) async throws -> [Data] {
        guard !isClosed else {
            throw ConnectionError.closed
        }
        logger.debug("sending request", metadata: ["kind": "\(request.kind)"])
        var data = try request.encode()
        logger.trace(
            "sending request",
            metadata: ["request": "\(request)", "dataChunks": "\(data.count)", "totalSize": "\(data.reduce(0) { $0 + $1.count })"]
        )
        let kind = request.kind
        let stream = try createStream(kind: kind)
        if data.isEmpty {
            try await stream.send(message: Data(), finish: true)
        } else {
            let last = data.removeLast()
            for chunk in data {
                try await stream.send(message: chunk)
            }
            try await stream.send(message: last, finish: true)
        }

        var resp = [Data]()
        while let data = try await receiveMaybeData(stream: stream) {
            resp.append(data)
        }
        return resp
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
                logger.warning("stream closed without receiving kind. status: \(stream.status)")
                return
            }
            if let upKind = Handler.PresistentHandler.StreamKind(rawValue: byte) {
                // Check for duplicate UP streams
                let existingStream = presistentStreams.read { presistentStreams in
                    presistentStreams[upKind]
                }
                if let existingStream {
                    if existingStream.stream.id < stream.stream.id {
                        // The new stream has a higher ID, so reset the existing one
                        existingStream.close(abort: false)
                        logger.info(
                            "Reset older UP stream with lower ID",
                            metadata: ["existingStreamId": "\(existingStream.stream.id)", "newStreamId": "\(stream.stream.id)"]
                        )
                    } else {
                        // The existing stream has a higher ID or is equal, so reset the new one
                        stream.close(abort: false)
                        logger.info(
                            "Duplicate UP stream detected, closing new stream with lower or equal ID",
                            metadata: ["existingStreamId": "\(existingStream.stream.id)", "newStreamId": "\(stream.stream.id)"]
                        )
                        return // Exit without replacing the existing stream
                    }
                }

                // Write the new stream as the active one for this UP kind
                presistentStreams.write { presistentStreams in
                    presistentStreams[upKind] = stream
                }
                runPresistentStreamLoop(stream: stream, kind: upKind)
                return
            }

            if let ceKind = Handler.EphemeralHandler.StreamKind(rawValue: byte) {
                logger.debug("stream opened. kind: \(ceKind)")

                var decoder = impl.ephemeralStreamHandler.createDecoder(kind: ceKind)

                do {
                    // receive all the data until no more
                    var allData = [Data]()
                    while let data = try await receiveMaybeData(stream: stream) {
                        allData.append(data)
                    }
                    let request = try decoder.decode(data: allData)
                    var resp = try await impl.ephemeralStreamHandler.handle(connection: self, request: request)
                    if resp.isEmpty {
                        stream.close()
                    } else {
                        let last = resp.removeLast()
                        for r in resp {
                            try await stream.send(message: r)
                        }
                        try await stream.send(message: last, finish: true)
                    }
                } catch {
                    logger.error("Failed to handle request", metadata: ["error": "\(error)"])
                    stream.close(abort: true)
                }
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

// expect length prefixed data
// stream close is an error
private func receiveData(stream: Stream<some StreamHandler>) async throws -> Data {
    let data = try await receiveMaybeData(stream: stream)
    guard let data else {
        throw ConnectionError.receiveFailed
    }
    return data
}

// stream close is not an error
private func receiveMaybeData(stream: Stream<some StreamHandler>) async throws -> Data? {
    let lengthData = await stream.receive(count: 4)
    guard let lengthData else {
        return nil
    }
    let length = UInt32(littleEndian: lengthData.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
    // sanity check for length
    // TODO: pick better value
    guard length < 1024 * 1024 * 10 else {
        stream.close(abort: true)
        logger.error("Invalid request length: \(length)")
        // TODO: report bad peer
        throw ConnectionError.invalidLength
    }
    return await stream.receive(count: Int(length))
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
            logger.error(
                "Failed to setup presistent stream",
                metadata: ["connectionId": "\(connection.id)", "streamId": "\(stream.id)", "error": "\(error)"]
            )
        }
        logger.debug(
            "Starting presistent stream run loop",
            metadata: ["connectionId": "\(connection.id)", "streamId": "\(stream.id)", "kind": "\(kind)"]
        )
        var decoder = handler.createDecoder(kind: kind)
        do {
            while let data = try await receiveMaybeData(stream: stream) {
                let msg = try decoder.decode(data: data)
                try await handler.handle(connection: connection, message: msg)
            }
        } catch {
            logger.error("UP stream run loop failed: \(error) \(connection.id) \(stream.id)")
            stream.close(abort: true)
        }

        logger.debug(
            "Ending presistent stream run loop",
            metadata: ["connectionId": "\(connection.id)", "streamId": "\(stream.id)", "kind": "\(kind)"]
        )
    }
}
