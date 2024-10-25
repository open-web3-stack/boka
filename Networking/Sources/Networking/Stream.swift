import AsyncChannels
import Foundation
import MsQuicSwift
import Synchronization
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
    private let nextData: Mutex<Data?> = .init(nil)
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
        try send(message: message.encode(), finish: false)
    }

    /// send raw data
    func send(data: Data, finish: Bool = false) throws {
        guard status == .open else {
            throw StreamError.notOpen
        }

        try stream.send(data: data, finish: finish)
    }

    // send message with length prefix
    func send(message: Data, finish: Bool = false) throws {
        guard status == .open else {
            throw StreamError.notOpen
        }

        let length = UInt32(message.count)
        var lengthData = Data(repeating: 0, count: 4)
        lengthData.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: UInt32(littleEndian: length), as: UInt32.self)
        }
        try stream.send(data: lengthData, finish: false)
        try stream.send(data: message, finish: finish)
    }

    func received(data: Data) {
        if !channel.syncSend(data) {
            logger.warning("stream \(id) is full")
            // TODO: backpressure handling
        }
    }

    // initiate stream close
    public func close(abort: Bool = false) {
        if status != .open {
            logger.warning("Trying to close stream \(id) in status \(status)")
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
        let data = nextData.withLock {
            let ret = $0
            $0 = nil
            return ret
        }
        if let data {
            return data
        }
        return await channel.receive()
    }

    func receive(count: Int) async -> Data? {
        guard var result = await receive() else {
            return nil
        }
        if result.count < count {
            guard let more = await receive(count: count - result.count) else {
                return nil
            }
            result.append(more)
            return result
        } else {
            let ret = result.prefix(count)
            nextData.withLock {
                $0 = result.dropFirst(count)
            }
            return ret
        }
    }

    func receiveByte() async -> UInt8? {
        await receive(count: 1)?.first
    }
}
