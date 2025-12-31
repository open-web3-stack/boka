import AsyncChannels
import Foundation
import MsQuicSwift
import Synchronization
import TracingUtils
import Utils

public enum StreamStatus: Sendable {
    // bidirection open
    case open
    // remote to local channel closed
    case sendOnly
    // local to remote channel closed
    case receiveOnly
    // stream completely closed
    case closed
    // stream aborted
    case aborted
}

enum StreamError: Error {
    case notOpen
}

public protocol StreamProtocol<Message> {
    associatedtype Message: MessageProtocol

    var id: UniqueId { get }
    var status: StreamStatus { get }
    func send(message: Message) async throws
    func close(abort: Bool)
}

actor StreamSender {
    private let stream: QuicStream
    private var status: StreamStatus

    init(stream: QuicStream, status: StreamStatus) {
        self.stream = stream
        self.status = status
    }

    func send(message: Data, finish: Bool = false) throws {
        guard status == .open || status == .sendOnly else {
            throw StreamError.notOpen
        }

        let length = UInt32(message.count)
        var lengthData = Data(repeating: 0, count: 4)
        lengthData.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: UInt32(littleEndian: length), as: UInt32.self)
        }

        try stream.send(data: lengthData, finish: false)
        try stream.send(data: message, finish: finish)

        if finish {
            switch status {
            case .open:
                status = .receiveOnly
            case .sendOnly:
                status = .closed
            default:
                unreachable("invalid status: \(status)")
            }
        }
    }
}

final class Stream<Handler: StreamHandler>: Sendable, StreamProtocol {
    typealias Message = Handler.PresistentHandler.Message

    private let logger: Logger

    let stream: QuicStream
    let impl: PeerImpl<Handler>
    private let channel: Channel<Data> = .init(capacity: 100)
    private let nextData: Mutex<Data?> = .init(nil)
    private let _status: ThreadSafeContainer<StreamStatus> = .init(.open)
    private let sender: StreamSender
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
        sender = StreamSender(stream: stream, status: .open)
    }

    public func send(message: Handler.PresistentHandler.Message) async throws {
        let data = try message.encode()
        for chunk in data {
            try await send(message: chunk, finish: false)
        }
    }

    /// send raw data
    func send(data: Data, finish: Bool = false) throws {
        guard status == .open else {
            throw StreamError.notOpen
        }

        try stream.send(data: data, finish: finish)
    }

    var canSend: Bool {
        status == .open || status == .sendOnly
    }

    var canReceive: Bool {
        status == .open || status == .receiveOnly
    }

    var ended: Bool {
        status == .closed || status == .aborted
    }

    // send message with length prefix
    func send(message: Data, finish: Bool = false) async throws {
        try await sender.send(message: message, finish: finish)
    }

    func received(data: Data?) {
        guard let data else {
            if !canReceive {
                logger.warning("unexpected status: \(status)")
            }
            status = .sendOnly
            channel.close()
            return
        }
        if data.isEmpty {
            return
        }
        guard canReceive else {
            logger.warning("unexpected status: \(status)")
            return
        }
        if !channel.syncSend(data) {
            logger.warning("stream \(id) is full")
            // TODO: backpressure handling
        }
    }

    // initiate stream close
    public func close(abort: Bool = false) {
        if ended {
            logger.warning("Trying to close stream \(id) in status \(status)")
            return
        }
        logger.debug("Closing stream \(id) in status \(status)")
        status = abort ? .aborted : .closed
        channel.close()
        let code = abort ? QuicErrorCode(ConnectionErrorCode.abort.rawValue) : QuicErrorCode(ConnectionErrorCode.normalClosure.rawValue)
        try? stream.shutdown(errorCode: code)
    }

    // remote initiated close
    func closed(abort: Bool = false) {
        status = abort ? .aborted : .closed
        channel.close()
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
