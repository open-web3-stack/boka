import AsyncChannels
import Foundation
import MsQuicSwift
import TracingUtils
import Utils

public enum StreamStatus: Sendable {
    case open, closed, aborted
}

enum StreamError: Error {
    case notOpen
}

public protocol StreamProtocol<Message> {
    associatedtype Message: MessageProtocol

    var id: UniqueId { get }
    var status: StreamStatus { get }
    func send(message: Message) throws
    func close(abort: Bool)
}

final class Stream<Handler: StreamHandler>: Sendable, StreamProtocol {
    typealias Message = Handler.PresistentHandler.Message

    private let logger: Logger

    let stream: QuicStream
    let impl: PeerImpl<Handler>
    private let channel: Channel<Data> = .init(capacity: 100)
    // TODO: https://github.com/gh123man/Async-Channels/issues/12
    private let nextData: ThreadSafeContainer<Data?> = .init(nil)
    private let _status: ThreadSafeContainer<StreamStatus> = .init(.open)
    let connectionId: UniqueId
    let kind: Handler.PresistentHandler.StreamKind?

    public var id: UniqueId {
        stream.id
    }

    public private(set) var status: StreamStatus {
        get {
            _status.value
        }
        set {
            _status.value = newValue
        }
    }

    init(_ stream: QuicStream, connectionId: UniqueId, impl: PeerImpl<Handler>, kind: Handler.PresistentHandler.StreamKind? = nil) {
        logger = Logger(label: "Stream#\(stream.id.idString)")
        self.stream = stream
        self.connectionId = connectionId
        self.impl = impl
        self.kind = kind
    }

    public func send(message: Handler.PresistentHandler.Message) throws {
        try send(data: message.encode(), finish: true)
    }

    func send(data: Data, finish: Bool = false) throws {
        guard status == .open else {
            throw StreamError.notOpen
        }
        try stream.send(data: data, finish: finish)
    }

    func received(data: Data) {
        if data.isEmpty {
            return
        }
        // TODO: backpressure handling
        // https://github.com/gh123man/Async-Channels/issues/11
        Task {
            await channel.send(data)
        }
    }

    // initiate stream close
    public func close(abort: Bool = false) {
        if status != .open {
            logger.warning("Trying to close stream \(stream.id) in status \(status)")
            return
        }
        status = abort ? .aborted : .closed
        channel.close()
        try? stream.shutdown(errorCode: abort ? 1 : 0) // TODO: define some error code
    }

    // remote initiated close
    func closed(abort: Bool = false) {
        status = abort ? .aborted : .closed
    }

    func receive() async -> Data? {
        if let data = nextData.value {
            nextData.value = nil
            return data
        }
        return await channel.receive()
    }

    func receiveByte() async -> UInt8? {
        if var data = nextData.value {
            let byte = data.removeFirst()
            if data.isEmpty {
                nextData.value = nil
            } else {
                nextData.value = data
            }
            return byte
        }

        guard var data = await receive() else {
            return nil
        }

        let byte = data.removeFirst()
        if !data.isEmpty {
            nextData.value = data
        }
        return byte
    }
}
