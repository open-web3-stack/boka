import Foundation
import LRUCache

public enum MemoryError: Swift.Error {
    case chunkNotFound(UInt32)
    case exceedChunkBoundary(UInt32)
    case notReadable(UInt32)
    case notWritable(UInt32)
    case outOfMemory(UInt32)
    case notContiguous(UInt32)

    public var address: UInt32 {
        switch self {
        case let .chunkNotFound(address):
            address
        case let .exceedChunkBoundary(address):
            address
        case let .notReadable(address):
            address
        case let .notWritable(address):
            address
        case let .outOfMemory(address):
            address
        case let .notContiguous(address):
            address
        }
    }
}

public enum PageAccess {
    case readOnly
    case readWrite
    case noAccess

    public func isReadable() -> Bool {
        switch self {
        case .readOnly:
            true
        case .readWrite:
            true
        case .noAccess:
            false
        }
    }

    public func isWritable() -> Bool {
        switch self {
        case .readWrite:
            true
        default:
            false
        }
    }
}

public protocol Memory {
    var pageMap: PageMap { get }

    func isReadable(address: UInt32, length: Int) -> Bool
    func isWritable(address: UInt32, length: Int) -> Bool
    func isReadable(pageStart: UInt32, pages: Int) -> Bool
    func isWritable(pageStart: UInt32, pages: Int) -> Bool

    func read(address: UInt32) throws -> UInt8
    func read(address: UInt32, length: Int) throws -> Data
    func write(address: UInt32, value: UInt8) throws
    func write(address: UInt32, values: some Sequence<UInt8>) throws

    func zero(pageIndex: UInt32, pages: Int) throws
    func void(pageIndex: UInt32, pages: Int) throws
    func sbrk(_ increment: UInt32) throws -> UInt32
}

public class PageMap {
    private var pageTable: [UInt32: PageAccess] = [:]
    private let config: PvmConfig

    // cache for multi page queries
    private var isReadableCache: LRUCache<Range<UInt32>, Bool>
    private var isWritableCache: LRUCache<Range<UInt32>, Bool>

    public init(pageMap: [(address: UInt32, length: UInt32, access: PageAccess)], config: PvmConfig) {
        self.config = config
        isReadableCache = LRUCache<Range<UInt32>, Bool>(totalCostLimit: 0, countLimit: 1024)
        isWritableCache = LRUCache<Range<UInt32>, Bool>(totalCostLimit: 0, countLimit: 1024)

        for entry in pageMap {
            let startIndex = entry.address / UInt32(config.pvmMemoryPageSize)
            let pages = StandardProgram.alignToPageSize(size: entry.length, config: config)

            for i in startIndex ..< startIndex + pages {
                pageTable[i] = entry.access
            }
        }
    }

    public func isReadable(pageStart: UInt32, pages: Int) -> Bool {
        let pageRange = pageStart ..< pageStart + UInt32(pages)

        let cacheValue = isReadableCache.value(forKey: pageRange)
        if let cacheValue {
            return cacheValue
        }

        var result = false
        for i in pageRange {
            result = result || (pageTable[i]?.isReadable() ?? false)
        }
        isReadableCache.setValue(result, forKey: pageRange)
        return result
    }

    public func isReadable(address: UInt32, length: Int) -> Bool {
        let startPageIndex = address / UInt32(config.pvmMemoryPageSize)
        let pages = StandardProgram.alignToPageSize(size: UInt32(length), config: config)
        return isReadable(pageStart: startPageIndex, pages: Int(pages))
    }

    public func isWritable(pageStart: UInt32, pages: Int) -> Bool {
        let pageRange = pageStart ..< pageStart + UInt32(pages)

        let cacheValue = isWritableCache.value(forKey: pageRange)
        if let cacheValue {
            return cacheValue
        }

        var result = false
        for i in pageRange {
            result = result && (pageTable[i]?.isWritable() ?? false)
        }
        isWritableCache.setValue(result, forKey: pageRange)
        return result
    }

    public func isWritable(address: UInt32, length: Int) -> Bool {
        let startPageIndex = address / UInt32(config.pvmMemoryPageSize)
        let pages = StandardProgram.alignToPageSize(size: UInt32(length), config: config)
        return isWritable(pageStart: startPageIndex, pages: Int(pages))
    }

    public func update(address: UInt32, length: Int, access: PageAccess) {
        let startPageIndex = address / UInt32(config.pvmMemoryPageSize)
        let pages = StandardProgram.alignToPageSize(size: UInt32(length), config: config)
        let pageRange = startPageIndex ..< startPageIndex + pages

        for i in pageRange {
            pageTable[i] = access
        }

        isReadableCache.removeAllValues()
        isWritableCache.removeAllValues()
    }

    public func update(pageIndex: UInt32, pages: Int, access: PageAccess) {
        for i in pageIndex ..< pageIndex + UInt32(pages) {
            pageTable[i] = access
        }
        isReadableCache.removeAllValues()
        isWritableCache.removeAllValues()
    }
}

public class MemoryChunk {
    public private(set) var startAddress: UInt32
    public private(set) var endAddress: UInt32
    public private(set) var data: Data

    public init(startAddress: UInt32, endAddress: UInt32, data: Data) {
        self.startAddress = startAddress
        self.endAddress = endAddress
        self.data = data
    }

    public func read(address: UInt32, length: Int) throws(MemoryError) -> Data {
        guard startAddress <= address, address + UInt32(length) < endAddress else {
            throw .exceedChunkBoundary(address)
        }
        let startIndex = address - startAddress
        let endIndex = startIndex + UInt32(length)

        let validCount = min(endIndex, UInt32(data.count))
        let dataToRead = data[startIndex ..< validCount]

        let zeroCount = max(0, Int(endIndex - validCount))
        let zeros = Data(repeating: 0, count: zeroCount)

        return dataToRead + zeros
    }

    public func write(address: UInt32, values: some Sequence<UInt8>) throws(MemoryError) {
        let valuesData = Data(values)
        guard startAddress <= address, address + UInt32(valuesData.count) < endAddress else {
            throw .exceedChunkBoundary(address)
        }

        let startIndex = address - startAddress
        let endIndex = startIndex + UInt32(valuesData.count)
        guard endIndex < data.count else {
            throw .notWritable(address)
        }

        data[startIndex ..< endIndex] = valuesData
    }

    public func incrementEnd(size increment: UInt32) throws(MemoryError) {
        guard endAddress + increment <= UInt32.max else {
            throw .outOfMemory(endAddress)
        }
        endAddress += increment
    }

    public func merge(chunk newChunk: MemoryChunk) throws(MemoryError) {
        guard newChunk.endAddress <= UInt32.max else {
            throw .outOfMemory(endAddress)
        }
        guard endAddress == newChunk.startAddress else {
            throw .notContiguous(newChunk.startAddress)
        }
        endAddress = newChunk.endAddress
        zeroPad()
        data.append(newChunk.data)
    }

    private func zeroPad() {
        if data.count < Int(endAddress - startAddress) {
            data.append(Data(repeating: 0, count: Int(endAddress - startAddress) - data.count))
        }
    }
}

/// Standard Program Memory
public class StandardMemory: Memory {
    public private(set) var pageMap: PageMap
    private let config: PvmConfig

    private var readOnly: MemoryChunk
    private var heap: MemoryChunk
    private var stack: MemoryChunk
    private var argument: MemoryChunk

    public init(readOnlyData: Data, readWriteData: Data, argumentData: Data, heapEmptyPagesSize: UInt32, stackSize: UInt32) {
        let config = DefaultPvmConfig()
        let P = StandardProgram.alignToPageSize
        let Q = StandardProgram.alignToZoneSize
        let ZZ = UInt32(config.pvmProgramInitZoneSize)

        let readOnlyLen = UInt32(readOnlyData.count)
        let readWriteLen = UInt32(readWriteData.count)

        let heapStart = 2 * ZZ + Q(readOnlyLen, config)
        let heapDataLen = P(readWriteLen, config)

        let stackPageAlignedSize = P(stackSize, config)
        let stackBaseAddr = UInt32(config.pvmProgramInitStackBaseAddress) - stackPageAlignedSize

        let argumentDataLen = UInt32(argumentData.count)

        readOnly = MemoryChunk(
            startAddress: ZZ,
            endAddress: ZZ + P(readOnlyLen, config),
            data: readOnlyData
        )

        heap = MemoryChunk(
            startAddress: heapStart,
            endAddress: heapStart + heapDataLen + heapEmptyPagesSize,
            data: readWriteData
        )
        stack = MemoryChunk(
            startAddress: stackBaseAddr,
            endAddress: UInt32(config.pvmProgramInitStackBaseAddress),
            data: Data(repeating: 0, count: Int(stackPageAlignedSize))
        )
        argument = MemoryChunk(
            startAddress: UInt32(config.pvmProgramInitInputStartAddress),
            endAddress: UInt32(config.pvmProgramInitInputStartAddress) + P(argumentDataLen, config),
            data: argumentData
        )

        pageMap = PageMap(pageMap: [
            (ZZ, P(readOnlyLen, config), .readOnly),
            (heapStart, heapDataLen + heapEmptyPagesSize, .readWrite),
            (stackBaseAddr, stackPageAlignedSize, .readWrite),
            (UInt32(config.pvmProgramInitInputStartAddress), P(argumentDataLen, config), .readOnly),
        ], config: config)

        self.config = config
    }

    private func getChunk(forAddress: UInt32) throws(MemoryError) -> MemoryChunk {
        let address = forAddress & UInt32.max
        if address >= readOnly.startAddress, address < readOnly.endAddress {
            return readOnly
        } else if address >= heap.startAddress, address < heap.endAddress {
            return heap
        } else if address >= stack.startAddress, address < stack.endAddress {
            return stack
        } else if address >= argument.startAddress, address < argument.endAddress {
            return argument
        }
        throw .chunkNotFound(address)
    }

    public func read(address: UInt32) throws(MemoryError) -> UInt8 {
        guard isReadable(address: address, length: 1) else {
            throw .notReadable(address)
        }
        return try getChunk(forAddress: address).read(address: address, length: 1).first ?? 0
    }

    public func read(address: UInt32, length: Int) throws(MemoryError) -> Data {
        guard isReadable(address: address, length: length) else {
            throw .notReadable(address)
        }
        return try getChunk(forAddress: address).read(address: address, length: length)
    }

    public func write(address: UInt32, value: UInt8) throws(MemoryError) {
        guard isWritable(address: address, length: 1) else {
            throw .notWritable(address)
        }
        try getChunk(forAddress: address).write(address: address, values: [value])
    }

    public func write(address: UInt32, values: some Sequence<UInt8>) throws(MemoryError) {
        guard isWritable(address: address, length: values.underestimatedCount) else {
            throw .notWritable(address)
        }
        try getChunk(forAddress: address).write(address: address, values: values)
    }

    public func zero(pageIndex: UInt32, pages: Int) throws {
        let address = pageIndex * UInt32(config.pvmMemoryPageSize)
        try getChunk(forAddress: address).write(
            address: address,
            values: Data(repeating: 0, count: Int(pages * config.pvmMemoryPageSize))
        )
        pageMap.update(pageIndex: pageIndex, pages: pages, access: .readWrite)
    }

    public func void(pageIndex: UInt32, pages: Int) throws {
        let address = pageIndex * UInt32(config.pvmMemoryPageSize)
        try getChunk(forAddress: address).write(
            address: address,
            values: Data(repeating: 0, count: Int(pages * config.pvmMemoryPageSize))
        )
        pageMap.update(pageIndex: pageIndex, pages: pages, access: .noAccess)
    }

    public func sbrk(_ increment: UInt32) throws(MemoryError) -> UInt32 {
        let prevHeapEnd = heap.endAddress
        guard prevHeapEnd + increment < stack.startAddress else {
            throw .outOfMemory(prevHeapEnd)
        }
        pageMap.update(address: prevHeapEnd, length: Int(increment), access: .readWrite)
        try heap.incrementEnd(size: increment)
        return prevHeapEnd
    }
}

/// General Program Memory
public class GeneralMemory: Memory {
    public private(set) var pageMap: PageMap
    private let config: PvmConfig
    // TODO: can be improved by using a more efficient data structure
    private var chunks: [MemoryChunk] = []

    public init(pageMap: [(address: UInt32, length: UInt32, writable: Bool)], chunks: [(address: UInt32, data: Data)]) throws {
        let config = DefaultPvmConfig()
        self.pageMap = PageMap(
            pageMap: pageMap.map { (address: $0.address, length: $0.length, access: $0.writable ? .readWrite : .readOnly) },
            config: config
        )
        for chunk in chunks {
            try GeneralMemory.insertChunk(address: chunk.address, data: chunk.data, chunks: &self.chunks)
        }
        self.config = config
    }

    // modify chunks array, always merge adjacent chunks, overwrite existing data
    // note: caller should rmb to handle corresponding page map updates
    private static func insertChunk(address: UInt32, data: Data, chunks: inout [MemoryChunk]) throws {
        let newEnd = address + UInt32(data.count)

        // find overlapping chunks
        var firstIndex = searchChunk(for: address, in: chunks).index
        if firstIndex > 0, chunks[firstIndex - 1].endAddress > address {
            firstIndex -= 1
        }
        var lastIndex = firstIndex
        while lastIndex < chunks.count, chunks[lastIndex].startAddress < newEnd {
            lastIndex += 1
        }

        // no overlaps
        if firstIndex == lastIndex {
            chunks.insert(MemoryChunk(startAddress: address, endAddress: newEnd, data: data), at: firstIndex)
            return
        }

        // have overlaps
        // calculate merged chunk boundaries
        let startAddr = min(chunks[firstIndex].startAddress, address)
        let endAddr = max(chunks[lastIndex - 1].endAddress, newEnd)
        let newChunk = MemoryChunk(startAddress: startAddr, endAddress: endAddr, data: Data())
        // merge existing chunks
        for i in firstIndex ..< lastIndex {
            try newChunk.merge(chunk: chunks[i])
        }
        // overwrite existing data with input
        try newChunk.write(address: address, values: data)
        // replace old chunks
        chunks.replaceSubrange(firstIndex ..< lastIndex, with: [newChunk])
    }

    // binary search for the index containing the address or index to to inserted
    private static func searchChunk(for address: UInt32, in chunks: [MemoryChunk]) -> (index: Int, found: Bool) {
        var low = 0
        var high = chunks.endIndex
        while low < high {
            let mid = low + (high - low) / 2
            if chunks[mid].startAddress < address {
                low = mid + 1
            } else if chunks[mid].startAddress > address {
                high = mid
            } else {
                return (mid, true)
            }
        }
        return (low, false)
    }

    private func getChunk(forAddress: UInt32) throws(MemoryError) -> MemoryChunk {
        let (index, found) = GeneralMemory.searchChunk(for: forAddress, in: chunks)
        if found {
            return chunks[index]
        }
        throw .chunkNotFound(forAddress)
    }

    public func read(address: UInt32) throws(MemoryError) -> UInt8 {
        guard isReadable(address: address, length: 1) else {
            throw .notReadable(address)
        }
        return try getChunk(forAddress: address).read(address: address, length: 1).first ?? 0
    }

    public func read(address: UInt32, length: Int) throws(MemoryError) -> Data {
        guard isReadable(address: address, length: length) else {
            throw .notReadable(address)
        }
        return try getChunk(forAddress: address).read(address: address, length: length)
    }

    public func write(address: UInt32, value: UInt8) throws(MemoryError) {
        guard isWritable(address: address, length: 1) else {
            throw .notWritable(address)
        }
        try getChunk(forAddress: address).write(address: address, values: [value])
    }

    public func write(address: UInt32, values: some Sequence<UInt8>) throws(MemoryError) {
        guard isWritable(address: address, length: values.underestimatedCount) else {
            throw .notWritable(address)
        }
        try getChunk(forAddress: address).write(address: address, values: values)
    }

    public func zero(pageIndex: UInt32, pages: Int) throws {
        try GeneralMemory.insertChunk(
            address: pageIndex * UInt32(config.pvmMemoryPageSize),
            data: Data(repeating: 0, count: Int(pages * config.pvmMemoryPageSize)),
            chunks: &chunks
        )
        pageMap.update(pageIndex: pageIndex, pages: pages, access: .readWrite)
    }

    public func void(pageIndex: UInt32, pages: Int) throws {
        try GeneralMemory.insertChunk(
            address: pageIndex * UInt32(config.pvmMemoryPageSize),
            data: Data(repeating: 0, count: Int(pages * config.pvmMemoryPageSize)),
            chunks: &chunks
        )
        pageMap.update(pageIndex: pageIndex, pages: pages, access: .noAccess)
    }

    public func sbrk(_ increment: UInt32) throws(MemoryError) -> UInt32 {
        // find a gap if any
        for i in 0 ..< chunks.count - 1 {
            let currentChunk = chunks[i]
            let nextChunk = chunks[i + 1]
            // check if there's enough space between the current and next chunk
            if currentChunk.endAddress + increment < nextChunk.startAddress {
                let prevEnd = currentChunk.endAddress
                try currentChunk.incrementEnd(size: increment)
                pageMap.update(address: prevEnd, length: Int(increment), access: .readWrite)
                // merge with the next chunk if they become adjacent
                if currentChunk.endAddress == nextChunk.startAddress {
                    try currentChunk.merge(chunk: nextChunk)
                    chunks.remove(at: i + 1)
                }
                return prevEnd
            }
        }
        // extend last chunk
        if let lastChunk = chunks.last {
            let prevEnd = lastChunk.endAddress
            try lastChunk.incrementEnd(size: increment)
            pageMap.update(address: prevEnd, length: Int(increment), access: .readWrite)
            return prevEnd
        }
        throw .outOfMemory(chunks.last?.endAddress ?? 0)
    }
}

extension Memory {
    public func isReadable(address: UInt32, length: Int) -> Bool {
        pageMap.isReadable(address: address, length: length)
    }

    public func isWritable(address: UInt32, length: Int) -> Bool {
        pageMap.isWritable(address: address, length: length)
    }

    public func isReadable(pageStart: UInt32, pages: Int) -> Bool {
        pageMap.isReadable(pageStart: pageStart, pages: pages)
    }

    public func isWritable(pageStart: UInt32, pages: Int) -> Bool {
        pageMap.isWritable(pageStart: pageStart, pages: pages)
    }
}

public class ReadonlyMemory {
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
