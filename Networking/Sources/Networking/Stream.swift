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
    private let receiveData: ThreadSafeContainer<[Data]> = .init([])
    private let _status: ThreadSafeContainer<StreamStatus> = .init(.open)
    let connectionId: UniqueId
    let kind: Handler.PresistentHandler.StreamKind?
    public var id: UniqueId {
        stream.id
    }

    let resendStates: ThreadSafeContainer<[UniqueId: BackoffState]> = .init([:])
    let maxRetryAttempts = 5

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
    func send(message: Data, finish: Bool = false) throws {
        guard canSend else {
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
            status = .receiveOnly
        }
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
            receiveData.write { receiveData in
                receiveData.append(data)
            }
            backpressure()
        }
    }

    /// Handles backpressure when sending data, adjusting flow control and retrying if necessary.
    private func backpressure() {
        var state = resendStates.read { resendStates in
            resendStates[id] ?? .init()
        }

        let sendData = receiveData.read { receiveData in
            receiveData.first
        }
        guard let sendData else {
            return
        }
        do {
            // Get the current flow control window size
            let windowsSize = try stream.getFlowControlWindow()

            guard state.attempt < maxRetryAttempts else {
                logger.warning("resend: \(id) reached max retry attempts")
                // close current stream
                close(abort: true)
                return
            }

            // Adjust flow control to half of the window size
            try stream.adjustFlowControl(windowSize: windowsSize >> 1)
            state.applyBackoff()
            resendStates.write { resendStates in
                resendStates[id] = state
            }

            Task {
                try await Task.sleep(for: .seconds(state.delay))
                if !channel.syncSend(sendData) {
                    logger.warning("stream \(id) is full")
                    backpressure() // Retry if sending fails
                } else {
                    try stream.adjustFlowControl(windowSize: Int(Int16.max))
                    _ = receiveData.write { receiveData in
                        receiveData.removeFirst()
                    }
                    resendStates.write { states in
                        states[id] = nil
                    }
                    backpressure()
                }
            }
        } catch {
            logger.error("backpressure: \(error)")
            // close current stream
            close(abort: true)
        }
    }

    // initiate stream close
    public func close(abort: Bool = false) {
        if ended {
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
