import Foundation
import LRUCache

public enum MemoryError: Error, Equatable {
    case chunkNotFound(UInt32)
    case exceedChunkBoundary(UInt32)
    case notReadable(UInt32)
    case notWritable(UInt32)
    case outOfMemory(UInt32)
    case notContiguous(UInt32)
    case invalidChunk(UInt32)

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
        case let .invalidChunk(address):
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
    private let isReadableCache: LRUCache<Range<UInt32>, Bool>
    private let isWritableCache: LRUCache<Range<UInt32>, Bool>

    public init(pageMap: [(address: UInt32, length: UInt32, access: PageAccess)], config: PvmConfig) {
        self.config = config
        isReadableCache = .init(totalCostLimit: 0, countLimit: 1024)
        isWritableCache = .init(totalCostLimit: 0, countLimit: 1024)

        for entry in pageMap {
            let startIndex = entry.address / UInt32(config.pvmMemoryPageSize)
            let pages = alignToNumberOfPages(size: entry.length)

            for i in startIndex ..< startIndex + pages {
                pageTable[i] = entry.access
            }
        }
    }

    private func alignToNumberOfPages(size: UInt32) -> UInt32 {
        let pageSize = UInt32(config.pvmMemoryPageSize)
        return (size + pageSize - 1) / pageSize
    }

    public func isReadable(pageStart: UInt32, pages: Int) -> Bool {
        if pages == 0 { return false }
        let pageRange = pageStart ..< pageStart + UInt32(pages)
        let cacheValue = isReadableCache.value(forKey: pageRange)
        if let cacheValue {
            return cacheValue
        }

        var result = true
        for i in pageRange {
            result = result && (pageTable[i]?.isReadable() ?? false)
        }
        isReadableCache.setValue(result, forKey: pageRange)
        return result
    }

    public func isReadable(address: UInt32, length: Int) -> Bool {
        let startPageIndex = address / UInt32(config.pvmMemoryPageSize)
        let pages = alignToNumberOfPages(size: UInt32(length))
        return isReadable(pageStart: startPageIndex, pages: Int(pages))
    }

    public func isWritable(pageStart: UInt32, pages: Int) -> Bool {
        if pages == 0 { return false }
        let pageRange = pageStart ..< pageStart + UInt32(pages)
        let cacheValue = isWritableCache.value(forKey: pageRange)
        if let cacheValue {
            return cacheValue
        }

        var result = true
        for i in pageRange {
            result = result && (pageTable[i]?.isWritable() ?? false)
        }
        isWritableCache.setValue(result, forKey: pageRange)
        return result
    }

    public func isWritable(address: UInt32, length: Int) -> Bool {
        let startPageIndex = address / UInt32(config.pvmMemoryPageSize)
        let pages = alignToNumberOfPages(size: UInt32(length))
        return isWritable(pageStart: startPageIndex, pages: Int(pages))
    }

    public func update(address: UInt32, length: Int, access: PageAccess) {
        let startPageIndex = address / UInt32(config.pvmMemoryPageSize)
        let pages = alignToNumberOfPages(size: UInt32(length))
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

    public init(startAddress: UInt32, endAddress: UInt32, data: Data) throws(MemoryError) {
        guard startAddress <= endAddress, endAddress - startAddress >= UInt32(data.count) else {
            throw .invalidChunk(startAddress)
        }
        self.startAddress = startAddress
        self.endAddress = endAddress
        self.data = data
    }

    public func read(address: UInt32, length: Int) throws(MemoryError) -> Data {
        guard startAddress <= address, address + UInt32(length) <= endAddress else {
            throw .exceedChunkBoundary(address)
        }
        let startIndex = Int(address - startAddress) + data.startIndex

        if startIndex >= data.endIndex {
            return Data(repeating: 0, count: length)
        } else {
            let validCount = min(length, data.endIndex - startIndex)
            let dataToRead = data.count > 0 ? data[startIndex ..< startIndex + validCount] : Data()

            let zeroCount = max(0, length - validCount)
            let zeros = Data(repeating: 0, count: zeroCount)

            return dataToRead + zeros
        }
    }

    public func write(address: UInt32, values: some Sequence<UInt8>) throws(MemoryError) {
        let valuesData = Data(values)
        guard startAddress <= address, address + UInt32(valuesData.count) <= endAddress else {
            throw .exceedChunkBoundary(address)
        }

        let startIndex = Int(address - startAddress) + data.startIndex
        let endIndex = startIndex + valuesData.count

        try zeroPad(until: startAddress + UInt32(endIndex))

        data.replaceSubrange(startIndex ..< endIndex, with: valuesData)
    }

    public func incrementEnd(size increment: UInt32) throws(MemoryError) {
        guard UInt32.max - endAddress >= increment else {
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
        try zeroPad()
        endAddress = newChunk.endAddress
        data.append(newChunk.data)
    }

    private func zeroPad(until address: UInt32? = nil) throws(MemoryError) {
        let end = address ?? endAddress
        guard end >= startAddress, end <= endAddress else {
            throw .exceedChunkBoundary(end)
        }
        if data.count < Int(end - startAddress) {
            data.append(Data(repeating: 0, count: Int(end - startAddress) - data.count))
        }
    }
}

/// Standard Program Memory
public class StandardMemory: Memory {
    public let pageMap: PageMap
    private let config: PvmConfig

    private let readOnly: MemoryChunk
    private let heap: MemoryChunk
    private let stack: MemoryChunk
    private let argument: MemoryChunk

    public init(readOnlyData: Data, readWriteData: Data, argumentData: Data, heapEmptyPagesSize: UInt32, stackSize: UInt32) throws {
        let config = DefaultPvmConfig()
        let P = StandardProgram.alignToPageSize
        let Z = StandardProgram.alignToZoneSize
        let ZZ = UInt32(config.pvmProgramInitZoneSize)

        let readOnlyLen = UInt32(readOnlyData.count)
        let readWriteLen = UInt32(readWriteData.count)

        let heapStart = 2 * ZZ + Z(readOnlyLen, config)
        let heapDataPagesLen = P(readWriteLen, config)

        let stackPageAlignedSize = P(stackSize, config)
        let stackStartAddr = UInt32(config.pvmProgramInitStackBaseAddress) - stackPageAlignedSize

        let argumentDataLen = UInt32(argumentData.count)

        readOnly = try MemoryChunk(
            startAddress: ZZ,
            endAddress: ZZ + P(readOnlyLen, config),
            data: readOnlyData
        )

        heap = try MemoryChunk(
            startAddress: heapStart,
            endAddress: heapStart + heapDataPagesLen + heapEmptyPagesSize,
            data: readWriteData
        )
        stack = try MemoryChunk(
            startAddress: stackStartAddr,
            endAddress: UInt32(config.pvmProgramInitStackBaseAddress),
            data: Data(repeating: 0, count: Int(stackPageAlignedSize))
        )
        argument = try MemoryChunk(
            startAddress: UInt32(config.pvmProgramInitInputStartAddress),
            endAddress: UInt32(config.pvmProgramInitInputStartAddress) + P(argumentDataLen, config),
            data: argumentData
        )

        pageMap = PageMap(pageMap: [
            (ZZ, P(readOnlyLen, config), .readOnly),
            (heapStart, heapDataPagesLen + heapEmptyPagesSize, .readWrite),
            (stackStartAddr, stackPageAlignedSize, .readWrite),
            (UInt32(config.pvmProgramInitInputStartAddress), P(argumentDataLen, config), .readOnly),
        ], config: config)

        self.config = config
    }

    private func getChunk(address: UInt32) throws(MemoryError) -> MemoryChunk {
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
        return try getChunk(address: address).read(address: address, length: 1).first ?? 0
    }

    public func read(address: UInt32, length: Int) throws(MemoryError) -> Data {
        guard isReadable(address: address, length: length) else {
            throw .notReadable(address)
        }
        return try getChunk(address: address).read(address: address, length: length)
    }

    public func write(address: UInt32, value: UInt8) throws(MemoryError) {
        guard isWritable(address: address, length: 1) else {
            throw .notWritable(address)
        }
        try getChunk(address: address).write(address: address, values: [value])
    }

    public func write(address: UInt32, values: some Sequence<UInt8>) throws(MemoryError) {
        guard isWritable(address: address, length: Data(values).count) else {
            throw .notWritable(address)
        }
        try getChunk(address: address).write(address: address, values: values)
    }

    // TODO: check whether need this
    public func zero(pageIndex: UInt32, pages: Int) throws {
        let address = pageIndex * UInt32(config.pvmMemoryPageSize)
        try getChunk(address: address).write(
            address: address,
            values: Data(repeating: 0, count: Int(pages * config.pvmMemoryPageSize))
        )
        pageMap.update(pageIndex: pageIndex, pages: pages, access: .readWrite)
    }

    // TODO: check whether need this
    public func void(pageIndex: UInt32, pages: Int) throws {
        let address = pageIndex * UInt32(config.pvmMemoryPageSize)
        try getChunk(address: address).write(
            address: address,
            values: Data(repeating: 0, count: Int(pages * config.pvmMemoryPageSize))
        )
        pageMap.update(pageIndex: pageIndex, pages: pages, access: .noAccess)
    }

    public func sbrk(_ increment: UInt32) throws(MemoryError) -> UInt32 {
        let prevHeapEnd = heap.endAddress
        let incrementAlignToPage = StandardProgram.alignToPageSize(size: increment, config: config)
        guard prevHeapEnd + incrementAlignToPage < stack.startAddress else {
            throw .outOfMemory(prevHeapEnd)
        }
        pageMap.update(address: prevHeapEnd, length: Int(incrementAlignToPage), access: .readWrite)
        try heap.incrementEnd(size: incrementAlignToPage)
        return prevHeapEnd
    }
}

/// General Program Memory
public class GeneralMemory: Memory {
    // TODO: check if need paged aligned access for general memory
    public let pageMap: PageMap
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

    // assume chunks is sorted by address
    // modify chunks array, always merge adjacent chunks, overwrite existing data
    // note: caller should rmb to handle corresponding page map updates
    private static func insertChunk(address: UInt32, data: Data, chunks: inout [MemoryChunk]) throws {
        let newEnd = address + UInt32(data.count)

        // new item at last index
        if address >= chunks.last?.endAddress ?? UInt32.max {
            let chunk = try MemoryChunk(startAddress: address, endAddress: newEnd, data: data)
            if chunks.last?.endAddress == address {
                try chunks.last?.merge(chunk: chunk)
                return
            } else {
                chunks.append(chunk)
                return
            }
        }

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
            try chunks.insert(MemoryChunk(startAddress: address, endAddress: newEnd, data: data), at: firstIndex)
            return
        }

        // have overlaps
        // calculate overlapping chunk boundaries
        let startAddr = min(chunks[firstIndex].startAddress, address)
        let endAddr = max(chunks[lastIndex - 1].endAddress, newEnd)
        let newChunk = try MemoryChunk(startAddress: startAddr, endAddress: endAddr, data: Data())
        for i in firstIndex ..< lastIndex {
            try newChunk.write(address: chunks[i].startAddress, values: chunks[i].data)
        }
        // lastly, overwrite existing data with input
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
            if chunks[mid].startAddress <= address, address < chunks[mid].endAddress {
                return (mid, true)
            } else if chunks[mid].startAddress > address {
                high = mid
            } else {
                low = mid + 1
            }
        }
        return (low, false)
    }

    private func getChunk(address: UInt32) throws(MemoryError) -> MemoryChunk {
        let (index, found) = GeneralMemory.searchChunk(for: address, in: chunks)
        if found {
            return chunks[index]
        }
        throw .chunkNotFound(address)
    }

    public func read(address: UInt32) throws(MemoryError) -> UInt8 {
        guard isReadable(address: address, length: 1) else {
            throw .notReadable(address)
        }
        return try getChunk(address: address).read(address: address, length: 1).first ?? 0
    }

    public func read(address: UInt32, length: Int) throws(MemoryError) -> Data {
        guard isReadable(address: address, length: length) else {
            throw .notReadable(address)
        }
        return try getChunk(address: address).read(address: address, length: length)
    }

    public func write(address: UInt32, value: UInt8) throws(MemoryError) {
        guard isWritable(address: address, length: 1) else {
            throw .notWritable(address)
        }
        try getChunk(address: address).write(address: address, values: [value])
    }

    public func write(address: UInt32, values: some Sequence<UInt8>) throws(MemoryError) {
        guard isWritable(address: address, length: Data(values).count) else {
            throw .notWritable(address)
        }
        try getChunk(address: address).write(address: address, values: values)
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
