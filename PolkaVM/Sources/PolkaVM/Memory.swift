import Foundation

public class Memory {
    public enum Error: Swift.Error {
        case pageFault(UInt32)
        case notWritable(UInt32)
        case outOfMemory(UInt32)

        public var address: UInt32 {
            switch self {
            case let .pageFault(address):
                address
            case let .notWritable(address):
                address
            case let .outOfMemory(address):
                address
            }
        }
    }

    private let pageMap: [(address: UInt32, length: UInt32, writable: Bool)]
    private var chunks: [(address: UInt32, data: Data)]
    private let heapStart: UInt32
    private var heapEnd: UInt32 // start idx of unallocated heap
    private let heapLimit: UInt32

    public init(pageMap: [(address: UInt32, length: UInt32, writable: Bool)], chunks: [(address: UInt32, data: Data)]) {
        self.pageMap = pageMap
        self.chunks = chunks
        heapStart = pageMap.first(where: { $0.writable })?.address ?? 0
        heapLimit = UInt32.max
        heapEnd = chunks.reduce(0) { max($0, $1.address + UInt32($1.data.count)) }
    }

    /// Standard Program init
    ///
    /// Init with some read only data, writable data and argument data
    public init(readOnlyData: Data, readWriteData: Data, argumentData: Data, heapEmptyPagesSize: UInt32, stackSize: UInt32) {
        let config = DefaultPvmConfig()
        let P = StandardProgram.alignToPageSize
        let Q = StandardProgram.alignToSegmentSize
        let ZQ = UInt32(config.pvmProgramInitSegmentSize)
        let readOnlyLen = UInt32(readOnlyData.count)
        let readWriteLen = UInt32(readWriteData.count)
        let argumentDataLen = UInt32(argumentData.count)

        let heapStart = 2 * ZQ + Q(readOnlyLen, config)

        pageMap = [
            (ZQ, readOnlyLen, false),
            (ZQ + readOnlyLen, P(readOnlyLen, config) - readOnlyLen, false),
            (heapStart, readWriteLen, true), // heap
            (heapStart + readWriteLen, P(readWriteLen, config) + heapEmptyPagesSize - readWriteLen, true), // heap
            (UInt32(config.pvmProgramInitStackBaseAddress) - P(stackSize, config), stackSize, true), // stack
            (UInt32(config.pvmProgramInitInputStartAddress), argumentDataLen, false), // argument
            (UInt32(config.pvmProgramInitInputStartAddress) + argumentDataLen, P(argumentDataLen, config) - argumentDataLen, false),
        ]

        chunks = [
            (ZQ, readOnlyData),
            (heapStart, readWriteData),
            (UInt32(config.pvmProgramInitInputStartAddress), argumentData),
        ]

        self.heapStart = heapStart
        heapLimit = heapStart + P(readWriteLen, config) + heapEmptyPagesSize
        heapEnd = heapStart + readWriteLen
    }

    public func isWritable(address: UInt32) -> Bool {
        // check heap range
        guard heapStart <= address, address < heapLimit else {
            return false
        }

        // TODO: optimize
        for page in pageMap {
            if page.address <= address, address < page.address + page.length {
                return page.writable
            }
        }

        return false
    }

    public func read(address: UInt32) throws(Error) -> UInt8 {
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
        throw Error.pageFault(address)
    }

    public func read(address: UInt32, length: Int) throws -> Data {
        // TODO: optimize this
        // check for chunks
        for chunk in chunks {
            if chunk.address <= address, address < chunk.address + UInt32(chunk.data.count) {
                let startIndex = Int(address - chunk.address)
                let endIndex = min(startIndex + length, chunk.data.endIndex)
                let res = chunk.data[startIndex ..< endIndex]
                let remaining = length - res.count
                if remaining == 0 {
                    return res
                } else {
                    let startAddress = chunk.address &+ UInt32(chunk.data.count) // wrapped add
                    let remainingData = try read(address: startAddress, length: remaining)
                    return res + remainingData
                }
            }
        }
        // check for page map
        for page in pageMap {
            if page.address <= address, address < page.address + page.length {
                // TODO: handle reads that cross page boundaries
                return Data(repeating: 0, count: length)
            }
        }
        throw Error.pageFault(address)
    }

    public func write(address: UInt32, value: UInt8) throws(Error) {
        guard isWritable(address: address) else {
            throw Error.notWritable(address)
        }

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
                heapEnd = max(heapEnd, address + 1)
                return
            }
        }
        throw Error.notWritable(address)
    }

    public func write(address: UInt32, values: some Sequence<UInt8>) throws(Error) {
        guard isWritable(address: address) else {
            throw Error.notWritable(address)
        }

        // TODO: optimize this
        // check for chunks
        for i in 0 ..< chunks.count {
            var chunk = chunks[i]
            if chunk.address <= address, address < chunk.address + UInt32(chunk.data.count) {
                var idx = Int(address - chunk.address)
                for v in values {
                    if idx == chunk.data.endIndex {
                        chunk.data.append(v)
                    } else {
                        chunk.data[idx] = v
                    }
                    idx += 1
                }
                chunks[i] = chunk
                return
            }
        }
        // check for page map
        for page in pageMap {
            if page.address <= address, address < page.address + page.length {
                var newChunk = (address: address, data: Data(repeating: 0, count: Int(page.length)))
                var idx = Int(address - page.address)
                for v in values {
                    if idx == newChunk.data.endIndex {
                        throw Error.notWritable(address)
                    } else {
                        newChunk.data[idx] = v
                    }
                    idx += 1
                }
                chunks.append(newChunk)
                heapEnd = max(heapEnd, UInt32(idx))
                return
            }
        }
        throw Error.notWritable(address)
    }

    public func sbrk(_ increment: UInt32) throws -> UInt32 {
        // TODO: optimize
        for page in pageMap {
            let pageEnd = page.address + page.length
            if page.writable, heapEnd >= page.address, heapEnd + increment < pageEnd {
                let newChunk = (address: heapEnd, data: Data(repeating: 0, count: Int(increment)))
                chunks.append(newChunk)
                heapEnd += increment
                return heapEnd
            }
        }

        throw Error.outOfMemory(heapEnd)
    }
}

extension Memory {
    public class Readonly {
        private let memory: Memory

        public init(_ memory: Memory) {
            self.memory = memory
        }

        public func read(address: UInt32) throws -> UInt8 {
            try memory.read(address: address)
        }

        public func read(address: UInt32, length: Int) throws -> Data {
            try memory.read(address: address, length: length)
        }
    }
}
