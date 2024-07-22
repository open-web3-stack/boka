import Foundation

public class Memory {
    public enum Error: Swift.Error {
        case pageFault
        case notWritable
    }

    private let pageMap: [(address: UInt32, length: UInt32, writable: Bool)]
    private var chunks: [(address: UInt32, data: Data)]

    public init(pageMap: [(address: UInt32, length: UInt32, writable: Bool)], chunks: [(address: UInt32, data: Data)]) {
        self.pageMap = pageMap
        self.chunks = chunks
    }

    public func read(_ address: UInt32) throws(Memory.Error) -> UInt8 {
        // TODO: optimize this
        // check for chunks
        for chunk in chunks {
            if chunk.address <= address, address < chunk.address + UInt32(chunk.data.count) {
                return chunk.data[Int(address - chunk.address)]
            }
        }
        // check for page map
        for page in pageMap {
            if page.address <= address, address < page.address + page.length {
                return 0
            }
        }
        throw Error.pageFault
    }

    public func write(address: UInt32, value: UInt8) throws(Memory.Error) {
        // TODO: optimize this
        // check for chunks
        for i in 0 ..< chunks.count {
            var chunk = chunks[i]
            if chunk.address <= address, address < chunk.address + UInt32(chunk.data.count) {
                chunk.data[Int(address - chunk.address)] = value
                chunks[i] = chunk
                return
            }
        }
        // check for page map
        for page in pageMap {
            if page.address <= address, address < page.address + page.length {
                var newChunk = (address: address, data: Data(repeating: 0, count: Int(page.length)))
                newChunk.data[Int(address - page.address)] = value
                chunks.append(newChunk)
                return
            }
        }
        throw Error.notWritable
    }
}
