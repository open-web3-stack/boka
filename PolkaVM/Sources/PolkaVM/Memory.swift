import Foundation
import LRUCache

public enum MemoryError: Error, Equatable {
    case zoneNotFound(UInt32)
    case chunkNotFound(UInt32)
    case invalidZone(UInt32)
    case exceedZoneBoundary(UInt32)
    case invalidChunk(UInt32)
    case exceedChunkBoundary(UInt32)
    case notReadable(UInt32)
    case notWritable(UInt32)
    case outOfMemory(UInt32)
    case notAdjacent(UInt32)

    // align to page start address
    private func alignToPageStart(address: UInt32) -> UInt32 {
        let config = DefaultPvmConfig()
        let pageSize = UInt32(config.pvmMemoryPageSize)
        return (address / pageSize) * pageSize
    }

    public var address: UInt32 {
        switch self {
        case let .zoneNotFound(address):
            alignToPageStart(address: address)
        case let .chunkNotFound(address):
            alignToPageStart(address: address)
        case let .invalidZone(address):
            alignToPageStart(address: address)
        case let .exceedZoneBoundary(address):
            alignToPageStart(address: address)
        case let .invalidChunk(address):
            alignToPageStart(address: address)
        case let .exceedChunkBoundary(address):
            alignToPageStart(address: address)
        case let .notReadable(address):
            alignToPageStart(address: address)
        case let .notWritable(address):
            alignToPageStart(address: address)
        case let .outOfMemory(address):
            alignToPageStart(address: address)
        case let .notAdjacent(address):
            alignToPageStart(address: address)
        }
    }
}

public enum PageAccess {
    case readOnly
    case readWrite

    public func isReadable() -> Bool {
        switch self {
        case .readOnly:
            true
        case .readWrite:
            true
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
    func write(address: UInt32, values: Data) throws

    func sbrk(_ increment: UInt32) throws -> UInt32
}

public class PageMap {
    // TODO: consider SortedDictionary
    private var pageTable: [UInt32: PageAccess] = [:]
    private let config: PvmConfig

    // cache for multi page queries
    // if the result is false, the page is the fault page, otherwise the page is the first page
    private let isReadableCache: LRUCache<Range<UInt32>, (result: Bool, page: UInt32)>
    private let isWritableCache: LRUCache<Range<UInt32>, (result: Bool, page: UInt32)>

    public init(pageMap: [(address: UInt32, length: UInt32, access: PageAccess)], config: PvmConfig) {
        self.config = config
        isReadableCache = .init(totalCostLimit: 0, countLimit: 1024)
        isWritableCache = .init(totalCostLimit: 0, countLimit: 1024)

        for entry in pageMap {
            let startIndex = entry.address / UInt32(config.pvmMemoryPageSize)
            let pages = numberOfPagesToAccess(address: entry.address, length: Int(entry.length))

            for i in startIndex ..< startIndex + pages {
                pageTable[i] = entry.access
            }
        }
    }

    private func numberOfPagesToAccess(address: UInt32, length: Int) -> UInt32 {
        if length == 0 {
            return 0
        }
        let addressPageIndex = address / UInt32(config.pvmMemoryPageSize)
        let endPageIndex = (address + UInt32(length) - 1) / UInt32(config.pvmMemoryPageSize)
        return endPageIndex - addressPageIndex + 1
    }

    /// If the pages are readable, return (true, pageStart)
    ///
    /// If the pages are not readable, return (false, faultPageIndex).
    public func isReadable(pageStart: UInt32, pages: Int) -> (result: Bool, page: UInt32) {
        if pages == 0 {
            return (pageTable[pageStart]?.isReadable() ?? false, pageStart)
        }
        let pageRange = pageStart ..< pageStart + UInt32(pages)
        let cacheValue = isReadableCache.value(forKey: pageRange)
        if let cacheValue {
            return cacheValue
        }

        var result = true
        var page = pageStart
        for i in pageRange {
            let curResult = pageTable[i]?.isReadable() ?? false
            if !curResult {
                result = false
                page = i
                break
            }
        }
        isReadableCache.setValue((result, page), forKey: pageRange)
        return (result, page)
    }

    /// If the pages are writable, return (true, address)
    ///
    /// If the pages are not writable, return (false, faultPage start address).
    public func isReadable(address: UInt32, length: Int) -> (result: Bool, address: UInt32) {
        let startPageIndex = address / UInt32(config.pvmMemoryPageSize)
        let pages = numberOfPagesToAccess(address: address, length: length)
        let (result, page) = isReadable(pageStart: startPageIndex, pages: Int(pages))
        return (result, page * UInt32(config.pvmMemoryPageSize))
    }

    /// If the pages are writable, return (true, pageStart)
    ///
    /// If the pages are not writable, return (false, faultPageIndex).
    public func isWritable(pageStart: UInt32, pages: Int) -> (result: Bool, page: UInt32) {
        if pages == 0 {
            return (pageTable[pageStart]?.isWritable() ?? false, pageStart)
        }
        let pageRange = pageStart ..< pageStart + UInt32(pages)
        let cacheValue = isWritableCache.value(forKey: pageRange)
        if let cacheValue {
            return cacheValue
        }

        var result = true
        var page = pageStart
        for i in pageRange {
            let curResult = pageTable[i]?.isWritable() ?? false
            if !curResult {
                result = false
                page = i
                break
            }
        }
        isWritableCache.setValue((result, page), forKey: pageRange)
        return (result, page)
    }

    /// If the pages are writable, return (true, address)
    ///
    /// If the pages are not writable, return (false, faultPage start address).
    public func isWritable(address: UInt32, length: Int) -> (result: Bool, address: UInt32) {
        let startPageIndex = address / UInt32(config.pvmMemoryPageSize)
        let pages = numberOfPagesToAccess(address: address, length: length)
        let (result, page) = isWritable(pageStart: startPageIndex, pages: Int(pages))
        return (result, page * UInt32(config.pvmMemoryPageSize))
    }

    public func update(address: UInt32, length: Int, access: PageAccess) {
        let startPageIndex = address / UInt32(config.pvmMemoryPageSize)
        let pages = numberOfPagesToAccess(address: address, length: length)
        let pageRange = startPageIndex ..< startPageIndex + pages

        for i in pageRange {
            pageTable[i] = access
        }

        isReadableCache.removeAllValues()
        isWritableCache.removeAllValues()
    }

    public func update(pageIndex: UInt32, pages: Int, access: PageAccess) {
        if pages == 0 {
            pageTable[pageIndex] = access
            return
        }
        for i in pageIndex ..< pageIndex + UInt32(pages) {
            pageTable[i] = access
        }
        isReadableCache.removeAllValues()
        isWritableCache.removeAllValues()
    }

    public func removeAccess(address: UInt32, length: Int) {
        let startPageIndex = address / UInt32(config.pvmMemoryPageSize)
        let pages = numberOfPagesToAccess(address: address, length: length)
        let pageRange = startPageIndex ..< startPageIndex + UInt32(pages)

        for i in pageRange {
            pageTable.removeValue(forKey: i)
        }
        isReadableCache.removeAllValues()
        isWritableCache.removeAllValues()
    }

    public func removeAccess(pageIndex: UInt32, pages: Int) {
        if pages == 0 {
            pageTable.removeValue(forKey: pageIndex)
            return
        }
        for i in pageIndex ..< pageIndex + UInt32(pages) {
            pageTable.removeValue(forKey: i)
        }
        isReadableCache.removeAllValues()
        isWritableCache.removeAllValues()
    }

    // find an inaccessible gap in page map if any
    // return the first page index of the gap
    public func findGapOrThrow(pages: Int) throws(MemoryError) -> UInt32 {
        let sortedKeys = pageTable.keys.sorted()

        for i in 0 ..< sortedKeys.count {
            let current = sortedKeys[i]
            let next = sortedKeys[i + 1]

            if next - current >= pages {
                return current + 1
            }
        }

        throw .outOfMemory(0)
    }
}

/// MemoryZone is an isolated memory area, used for stack, heap, arguments, etc.
public class MemoryZone {
    private let config: PvmConfig
    public let startAddress: UInt32
    public private(set) var endAddress: UInt32

    // TODO: could be optimized by using a more efficient data structure
    public private(set) var chunks: [MemoryChunk] = []

    public init(startAddress: UInt32, endAddress: UInt32, chunks: [MemoryChunk]) throws(MemoryError) {
        guard startAddress <= endAddress, (chunks.isSorted { $0.endAddress < $1.startAddress }) else {
            throw .invalidZone(startAddress)
        }

        if let last = chunks.last, endAddress < last.endAddress {
            throw .invalidZone(startAddress)
        }

        self.startAddress = startAddress
        self.endAddress = endAddress
        self.chunks = chunks
        config = DefaultPvmConfig()
    }

    // binary search for the index containing the address or index to be inserted
    private func searchChunk(for address: UInt32) -> (index: Int, found: Bool) {
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

    /// Insert or update the chunks, overwrite overlapping data.
    /// Return index of the chunk containing the address.
    ///
    /// Note this method assumes chunks are sorted by address.
    /// Note caller should remember to handle corresponding page map updates
    private func insertOrUpdate(address chunkStart: UInt32, data: Data) throws -> Int {
        // use the longer one as the chunk end address
        let chunkEnd = chunkStart + UInt32(data.count)

        // insert new chunk at the end
        if chunkStart >= chunks.last?.endAddress ?? UInt32.max {
            let chunk = try MemoryChunk(startAddress: chunkStart, data: data)
            if chunks.last?.endAddress == chunkStart {
                try chunks.last?.append(chunk: chunk)
                return chunks.endIndex - 1
            } else {
                chunks.append(chunk)
                return chunks.endIndex - 1
            }
        }

        // find overlapping chunks
        var firstIndex = searchChunk(for: chunkStart).index
        if firstIndex > 0, chunks[firstIndex - 1].endAddress > chunkStart {
            firstIndex -= 1
        }
        var lastIndex = firstIndex
        while lastIndex < chunks.count, chunks[lastIndex].startAddress < chunkEnd {
            lastIndex += 1
        }

        // no overlaps
        if firstIndex == lastIndex {
            try chunks.insert(MemoryChunk(startAddress: chunkStart, data: data), at: firstIndex)
            return firstIndex
        }

        // have overlaps
        // calculate overlapping chunk boundaries
        let startAddr = min(chunks[firstIndex].startAddress, chunkStart)
        let endAddr = max(chunks[lastIndex - 1].endAddress, chunkEnd)
        let newChunk = try MemoryChunk(startAddress: startAddr, data: Data())
        try newChunk.zeroExtend(until: endAddr)
        // merge overlapping part into a new chunk
        for i in firstIndex ..< lastIndex {
            try newChunk.write(address: chunks[i].startAddress, values: chunks[i].data)
        }
        // overwrite overlapping part with input data
        try newChunk.write(address: chunkStart, values: data)
        // replace overlapping chunks
        chunks.replaceSubrange(firstIndex ..< lastIndex, with: [newChunk])

        return firstIndex
    }

    public func read(address: UInt32, length: Int) throws -> Data {
        guard length > 0 else { return Data() }
        let readEnd = address &+ UInt32(length)
        guard readEnd >= address else { throw MemoryError.outOfMemory(readEnd) }
        guard endAddress >= readEnd else { throw MemoryError.exceedZoneBoundary(endAddress) }

        let (startIndex, _) = searchChunk(for: address)
        var res = Data()
        var curAddr = address
        var curChunkIndex = startIndex

        while curAddr < readEnd, curChunkIndex < chunks.endIndex {
            let chunk = chunks[curChunkIndex]
            // handle gap before chunk
            if curAddr < chunk.startAddress {
                let gapSize = min(chunk.startAddress - curAddr, readEnd - curAddr)
                res.append(Data(repeating: 0, count: Int(gapSize)))
                curAddr += gapSize
                continue
            }
            // handle chunk content
            if curAddr >= chunk.endAddress {
                curChunkIndex += 1
                continue
            }
            let chunkOffset = Int(curAddr - chunk.startAddress)
            let bytesToRead = min(chunk.data.count - chunkOffset, Int(readEnd - curAddr))
            res.append(chunk.data[relative: chunkOffset ..< chunkOffset + bytesToRead])
            curAddr += UInt32(bytesToRead)
            curChunkIndex += 1
        }

        // handle remaining space after last chunk
        if curAddr < readEnd {
            res.append(Data(repeating: 0, count: Int(readEnd - curAddr)))
        }
        return res
    }

    public func write(address: UInt32, values: Data) throws {
        _ = try insertOrUpdate(address: address, data: values)
    }

    public func incrementEnd(size increment: UInt32) throws(MemoryError) {
        guard endAddress <= UInt32.max - increment else {
            throw .outOfMemory(endAddress)
        }
        endAddress += increment
    }

    public func zero(pageIndex: UInt32, pages: Int) throws {
        _ = try insertOrUpdate(
            address: pageIndex * UInt32(config.pvmMemoryPageSize),
            data: Data(repeating: 0, count: Int(pages * config.pvmMemoryPageSize))
        )
    }

    // TODO: check if this will change to remove data
    public func void(pageIndex: UInt32, pages: Int) throws {
        _ = try insertOrUpdate(
            address: pageIndex * UInt32(config.pvmMemoryPageSize),
            data: Data(repeating: 0, count: Int(pages * config.pvmMemoryPageSize))
        )
    }
}

public class MemoryChunk {
    public private(set) var startAddress: UInt32
    public var endAddress: UInt32 {
        startAddress + UInt32(data.count)
    }

    public private(set) var data: Data

    public init(startAddress: UInt32, data: Data) throws(MemoryError) {
        let endAddress = startAddress + UInt32(data.count)
        guard startAddress <= endAddress, endAddress - startAddress >= UInt32(data.count) else {
            throw .invalidChunk(startAddress)
        }
        self.startAddress = startAddress
        self.data = data
    }

    // append another adjacent chunk
    public func append(chunk: MemoryChunk) throws(MemoryError) {
        guard endAddress == chunk.startAddress else {
            throw .notAdjacent(chunk.startAddress)
        }
        guard chunk.endAddress <= UInt32.max else {
            throw .outOfMemory(endAddress)
        }
        data.append(chunk.data)
    }

    public func zeroExtend(until address: UInt32) throws(MemoryError) {
        guard address <= UInt32.max else {
            throw .outOfMemory(endAddress)
        }
        data.append(Data(repeating: 0, count: Int(address - startAddress) - data.count))
    }

    public func read(address: UInt32, length: Int) throws(MemoryError) -> Data {
        guard startAddress <= address, address + UInt32(length) <= endAddress else {
            throw .exceedChunkBoundary(address)
        }
        let startIndex = Int(address - startAddress) + data.startIndex

        return data[startIndex ..< startIndex + length]
    }

    public func write(address: UInt32, values: Data) throws(MemoryError) {
        guard startAddress <= address, address + UInt32(values.count) <= endAddress else {
            throw .exceedChunkBoundary(address)
        }

        let startIndex = Int(address - startAddress) + data.startIndex
        let endIndex = startIndex + values.count

        data.replaceSubrange(startIndex ..< endIndex, with: values)
    }
}

/// Standard Program Memory
public class StandardMemory: Memory {
    public let pageMap: PageMap
    private let config: PvmConfig

    private let readOnly: MemoryZone
    private let heap: MemoryZone
    private let stack: MemoryZone
    private let argument: MemoryZone

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

        readOnly = try MemoryZone(
            startAddress: ZZ,
            endAddress: ZZ + P(readOnlyLen, config),
            chunks: [MemoryChunk(startAddress: ZZ, data: readOnlyData)]
        )

        heap = try MemoryZone(
            startAddress: heapStart,
            endAddress: heapStart + heapDataPagesLen + heapEmptyPagesSize,
            chunks: [MemoryChunk(startAddress: heapStart, data: readWriteData)]
        )
        stack = try MemoryZone(
            startAddress: stackStartAddr,
            endAddress: UInt32(config.pvmProgramInitStackBaseAddress),
            chunks: [MemoryChunk(startAddress: stackStartAddr, data: Data(repeating: 0, count: Int(stackPageAlignedSize)))]
        )
        argument = try MemoryZone(
            startAddress: UInt32(config.pvmProgramInitInputStartAddress),
            endAddress: UInt32(config.pvmProgramInitInputStartAddress) + P(argumentDataLen, config),
            chunks: [MemoryChunk(startAddress: UInt32(config.pvmProgramInitInputStartAddress), data: argumentData)]
        )

        pageMap = PageMap(pageMap: [
            (ZZ, P(readOnlyLen, config), .readOnly),
            (heapStart, heapDataPagesLen + heapEmptyPagesSize, .readWrite),
            (stackStartAddr, stackPageAlignedSize, .readWrite),
            (UInt32(config.pvmProgramInitInputStartAddress), P(argumentDataLen, config), .readOnly),
        ], config: config)

        self.config = config
    }

    private func getZone(address: UInt32) throws(MemoryError) -> MemoryZone {
        if address >= readOnly.startAddress, address < readOnly.endAddress {
            return readOnly
        } else if address >= heap.startAddress, address < heap.endAddress {
            return heap
        } else if address >= stack.startAddress, address < stack.endAddress {
            return stack
        } else if address >= argument.startAddress, address < argument.endAddress {
            return argument
        }
        throw .zoneNotFound(address)
    }

    public func read(address: UInt32) throws -> UInt8 {
        try ensureReadable(address: address, length: 1)
        return try getZone(address: address).read(address: address, length: 1).first ?? 0
    }

    public func read(address: UInt32, length: Int) throws -> Data {
        try ensureReadable(address: address, length: length)
        return try getZone(address: address).read(address: address, length: length)
    }

    public func write(address: UInt32, value: UInt8) throws {
        try ensureWritable(address: address, length: 1)
        try getZone(address: address).write(address: address, values: Data([value]))
    }

    public func write(address: UInt32, values: Data) throws {
        try ensureWritable(address: address, length: values.count)
        try getZone(address: address).write(address: address, values: values)
    }

    public func sbrk(_ size: UInt32) throws(MemoryError) -> UInt32 {
        // NOTE: sbrk will be removed from GP
        // NOTE: this impl aligns with w3f traces test vector README

        let prevHeapEnd = heap.endAddress
        if size == 0 {
            return prevHeapEnd
        }

        let nextPageBoundary = StandardProgram.alignToPageSize(size: prevHeapEnd, config: config)
        try heap.incrementEnd(size: size)

        if heap.endAddress > nextPageBoundary {
            let finalBoundary = heap.endAddress
            let start = nextPageBoundary / UInt32(config.pvmMemoryPageSize)
            let end = finalBoundary / UInt32(config.pvmMemoryPageSize)
            let count = Int(end - start)
            pageMap.update(pageIndex: start, pages: count, access: .readWrite)
        }

        return prevHeapEnd
    }
}

/// General Program Memory
public class GeneralMemory: Memory {
    private let config: PvmConfig
    public let pageMap: PageMap

    // general memory has a single zone
    private let zone: MemoryZone

    public init(pageMap: [(address: UInt32, length: UInt32, writable: Bool)], chunks: [(address: UInt32, data: Data)]) throws {
        let config = DefaultPvmConfig()
        self.pageMap = PageMap(
            pageMap: pageMap.map { (address: $0.address, length: $0.length, access: $0.writable ? .readWrite : .readOnly) },
            config: config
        )

        let memoryChunks = try chunks.map { chunk in
            try MemoryChunk(startAddress: chunk.address, data: chunk.data)
        }

        zone = try MemoryZone(startAddress: 0, endAddress: UInt32.max, chunks: memoryChunks)
        self.config = config
    }

    public func read(address: UInt32) throws -> UInt8 {
        try ensureReadable(address: address, length: 1)
        return try zone.read(address: address, length: 1).first ?? 0
    }

    public func read(address: UInt32, length: Int) throws -> Data {
        try ensureReadable(address: address, length: length)
        return try zone.read(address: address, length: length)
    }

    public func write(address: UInt32, value: UInt8) throws {
        try ensureWritable(address: address, length: 1)
        try zone.write(address: address, values: Data([value]))
    }

    public func write(address: UInt32, values: Data) throws {
        try ensureWritable(address: address, length: values.count)
        try zone.write(address: address, values: values)
    }

    public func zero(pageIndex: UInt32, pages: Int) throws {
        try zone.zero(pageIndex: pageIndex, pages: pages)
        pageMap.update(pageIndex: pageIndex, pages: pages, access: .readWrite)
    }

    public func void(pageIndex: UInt32, pages: Int) throws {
        try zone.void(pageIndex: pageIndex, pages: pages)
        pageMap.removeAccess(pageIndex: pageIndex, pages: pages)
    }

    public func sbrk(_ size: UInt32) throws(MemoryError) -> UInt32 {
        let pages = (Int(size) + config.pvmMemoryPageSize - 1) / config.pvmMemoryPageSize
        let page = try pageMap.findGapOrThrow(pages: pages)
        pageMap.update(pageIndex: page, pages: pages, access: .readWrite)

        return page * UInt32(config.pvmMemoryPageSize)
    }
}

extension Memory {
    public func isReadable(address: UInt32, length: Int) -> Bool {
        if length == 0 { return true }
        return pageMap.isReadable(address: address, length: length).result
    }

    public func isReadable(pageStart: UInt32, pages: Int) -> Bool {
        pageMap.isReadable(pageStart: pageStart, pages: pages).result
    }

    public func ensureReadable(address: UInt32, length: Int) throws(MemoryError) {
        let (result, address) = pageMap.isReadable(address: address, length: length)
        guard result else {
            throw .notReadable(address)
        }
    }

    public func isWritable(address: UInt32, length: Int) -> Bool {
        if length == 0 { return true }
        return pageMap.isWritable(address: address, length: length).result
    }

    public func isWritable(pageStart: UInt32, pages: Int) -> Bool {
        pageMap.isWritable(pageStart: pageStart, pages: pages).result
    }

    public func ensureWritable(address: UInt32, length: Int) throws(MemoryError) {
        let (result, address) = pageMap.isWritable(address: address, length: length)
        guard result else {
            throw .notWritable(address)
        }
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
