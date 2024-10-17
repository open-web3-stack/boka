import Dispatch
import Foundation
import Synchronization

/// A async data input
/// NOTE: the reading operation are blocking when buffer is empty
/// so they should be used on a detached task
/// This should only be used with single producer and single consumer
public final class AsyncDataInput: Sendable {
    private let chunks: Mutex<[Data]> = .init([])
    private let closed: Atomic<Bool> = .init(false)

    // every push do signal
    // every pop do wait
    private let semphore: DispatchSemaphore = .init(value: 0)

    public init() {}

    public func append(data: Data) {
        if data.isEmpty {
            return
        }
        chunks.withLock { chunks in
            chunks.append(data)
        }
        semphore.signal()
    }

    public func close() {
        closed.store(true, ordering: .releasing)
        semphore.signal()
    }
}

extension AsyncDataInput: DataInput {
    private func readChunkOrWait(upto: Int? = nil) -> Data? {
        semphore.wait()
        let closed = closed.load(ordering: .acquiring)
        if closed {
            return nil
        }
        let data = chunks.withLock { chunks -> Data? in
            if let chunk = chunks.first {
                if let upto, chunk.count > upto {
                    chunks[0] = chunk[upto ..< chunk.endIndex]
                } else {
                    chunks.removeFirst()
                }
                return chunk
            }
            // this should never happen as we waited for signal
            return nil
        }
        return data
    }

    public func read(length: Int) throws -> Data {
        var data = Data()
        while data.count < length {
            let chunk = readChunkOrWait(upto: length - data.count)
            guard let chunk else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: [],
                        debugDescription: "Not enough data to decode \(length) bytes"
                    )
                )
            }
            data.append(chunk)
        }
        return data
    }

    public var isEmpty: Bool {
        chunks.withLock { chunks in
            chunks.isEmpty
        }
    }
}
