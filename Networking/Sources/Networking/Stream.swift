import AsyncChannels
import Foundation
import MsQuicSwift
import Utils

public enum StreamStatus: Sendable {
    case open, closed, aborted
}

enum StreamError: Error {
    case notOpen
}

public final class Stream: Sendable {
    let stream: QuicStream
    let impl: PeerImpl
    private let channel: Channel<Data> = .init(capacity: 100)
    // TODO: https://github.com/gh123man/Async-Channels/issues/12
    private let nextData: ThreadSafeContainer<Data?> = .init(nil)
    private let _status: ThreadSafeContainer<StreamStatus> = .init(.open)

    public private(set) var status: StreamStatus {
        get {
            _status.value
        }
        set {
            _status.value = newValue
        }
    }

    init(_ stream: QuicStream, impl: PeerImpl) {
        self.stream = stream
        self.impl = impl
    }

    public func send(data: Data) throws {
        guard status == .open else {
            throw StreamError.notOpen
        }
        try stream.send(data: data)
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

    func close() {
        status = .closed
        channel.close()
    }

    func abort() {
        status = .aborted
        channel.close()
    }

    public func receive() async -> Data? {
        if let data = nextData.value {
            nextData.value = nil
            return data
        }
        return await channel.receive()
    }

    public func receiveByte() async -> UInt8? {
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
